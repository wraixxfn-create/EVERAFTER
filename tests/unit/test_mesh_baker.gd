class_name TestMeshBaker
extends RefCounted
## Checks for `MeshBaker`, and in particular for the thing that is easiest to get
## wrong and most expensive to discover late: **winding order**.
##
## Godot 4.7.2 was measured to derive the normal of a triangle `(a, b, c)` as
## `(c - a) x (b - a)`. If the baker emitted the opposite order, every surface
## would face inwards and back face culling would simply delete the village. The
## terrain of the previous phase had exactly that bug and nothing caught it.

const EPSILON := 0.0001


static func run_tests(harness: TestHarness) -> void:
	harness.suite("MeshBaker")

	var materials := VillageMaterials.new()

	# --- one mesh per material -----------------------------------------------
	var baker := MeshBaker.new()
	baker.add_box("stone", Vector3.ONE)
	baker.add_box("stone", Vector3.ONE, Transform3D(Basis.IDENTITY, Vector3(3, 0, 0)))
	baker.add_box("timber", Vector3.ONE, Transform3D(Basis.IDENTITY, Vector3(6, 0, 0)))
	harness.check_equals(
		baker.get_triangle_count(), 36, "three boxes are 36 triangles"
	)
	harness.check_equals(
		baker.get_material_keys_used(),
		PackedStringArray(["stone", "timber"]),
		"solids are grouped by material"
	)
	var baked: Array = baker.commit(materials)
	harness.check_equals(baked.size(), 2, "commit produces one mesh per material")
	for node in baked:
		(node as MeshInstance3D).free()

	# --- box winding and normals ---------------------------------------------
	var box_baker := MeshBaker.new()
	box_baker.add_box("stone", Vector3(2, 2, 2))
	var box_arrays := _first_surface(box_baker, materials)
	harness.check(not box_arrays.is_empty(), "a baked box has a surface")
	if box_arrays.is_empty():
		return
	var vertices: PackedVector3Array = box_arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = box_arrays[Mesh.ARRAY_NORMAL]
	harness.check_equals(vertices.size(), 36, "a box is 12 triangles, 36 vertices")
	harness.check_equals(normals.size(), vertices.size(), "every vertex has a normal")
	harness.check_equals(
		_bad_windings(vertices, normals, Vector3.ZERO),
		0,
		"every box triangle faces away from the box centre"
	)

	# --- cylinder and sphere windings ----------------------------------------
	var round_baker := MeshBaker.new()
	round_baker.add_cylinder("trunk", 0.5, 0.5, 2.0, 8)
	var cylinder_arrays := _first_surface(round_baker, materials)
	harness.check_equals(
		_bad_windings(
			cylinder_arrays[Mesh.ARRAY_VERTEX],
			cylinder_arrays[Mesh.ARRAY_NORMAL],
			Vector3.ZERO
		),
		0,
		"every cylinder triangle faces outwards"
	)
	var sphere_baker := MeshBaker.new()
	sphere_baker.add_sphere("rock", 1.0, 4, 6)
	var sphere_arrays := _first_surface(sphere_baker, materials)
	harness.check(
		sphere_arrays[Mesh.ARRAY_VERTEX].size() > 30, "a sphere is tessellated"
	)
	harness.check_equals(
		_bad_windings(
			sphere_arrays[Mesh.ARRAY_VERTEX], sphere_arrays[Mesh.ARRAY_NORMAL], Vector3.ZERO
		),
		0,
		"every sphere triangle faces outwards"
	)
	for node in round_baker.commit(materials) + sphere_baker.commit(materials):
		(node as MeshInstance3D).free()

	# --- prism -----------------------------------------------------------------
	var prism_baker := MeshBaker.new()
	prism_baker.add_prism("roof_tile", 4.0, 2.0, 3.0)
	var prism_arrays := _first_surface(prism_baker, materials)
	harness.check_equals(
		prism_arrays[Mesh.ARRAY_VERTEX].size(),
		18,
		"a prism is 6 triangles: two ends and two slopes"
	)
	var highest := -INF
	for vertex in prism_arrays[Mesh.ARRAY_VERTEX]:
		highest = maxf(highest, vertex.y)
	harness.check_almost(highest, 1.0, EPSILON, "the prism apex is at half its height")
	for node in prism_baker.commit(materials):
		(node as MeshInstance3D).free()

	# --- transforms ------------------------------------------------------------
	var moved := MeshBaker.new()
	moved.add_box(
		"stone", Vector3.ONE, Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, 0.0))
	)
	var moved_arrays := _first_surface(moved, materials)
	var centroid := Vector3.ZERO
	for vertex in moved_arrays[Mesh.ARRAY_VERTEX]:
		centroid += vertex
	centroid /= float(moved_arrays[Mesh.ARRAY_VERTEX].size())
	harness.check_almost(centroid.x, 10.0, EPSILON, "the transform places the solid")
	for node in moved.commit(materials):
		(node as MeshInstance3D).free()

	# --- vertex colours ----------------------------------------------------------
	var tinted := MeshBaker.new()
	tinted.add_box("stone", Vector3.ONE, Transform3D.IDENTITY, Color(0.5, 0.5, 0.5))
	var tinted_arrays := _first_surface(tinted, materials)
	var colors: PackedColorArray = tinted_arrays[Mesh.ARRAY_COLOR]
	harness.check_equals(colors.size(), 36, "every vertex carries a tint")
	# Mesh colours are stored as 8 bit unorm, so 0.5 comes back as 127/255.
	harness.check_almost(colors[0].r, 0.5, 0.01, "the tint is written to the mesh")
	harness.check(
		materials.get_material("stone").vertex_color_use_as_albedo,
		"materials read vertex colours as albedo, or the tint would be ignored"
	)
	for node in tinted.commit(materials):
		(node as MeshInstance3D).free()


## Counts triangles whose winding disagrees with their own written normal, using
## the rule measured on the engine. Zero means the mesh will be seen from the
## side its normals point to.
static func _bad_windings(
	vertices: PackedVector3Array, normals: PackedVector3Array, center: Vector3
) -> int:
	var bad := 0
	for index in range(0, vertices.size(), 3):
		var a := vertices[index]
		var b := vertices[index + 1]
		var c := vertices[index + 2]
		var wound := (c - a).cross(b - a)
		if wound.length_squared() < EPSILON:
			continue
		wound = wound.normalized()
		if wound.dot(normals[index]) < 0.5:
			bad += 1
		elif (a - center).length_squared() > EPSILON:
			# Outward, for a solid centred on `center`.
			if wound.dot((a - center).normalized()) < 0.0:
				bad += 1
	return bad


static func _first_surface(baker: MeshBaker, materials: VillageMaterials) -> Array:
	var baked: Array = baker.commit(materials)
	if baked.is_empty():
		return []
	var instance := baked[0] as MeshInstance3D
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	instance.free()
	return arrays
