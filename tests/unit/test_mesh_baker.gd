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
	harness.check_equals(
		round_baker.get_triangle_count(), 32,
		"an eight-sided cylinder has one top and bottom cap, not eight duplicates"
	)
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

	# Optional face tinting gives stone and timber blocks enough tonal structure
	# to read as separate surfaces while leaving the default box path unchanged.
	var faceted_box := MeshBaker.new()
	faceted_box.add_box("stone", Vector3.ONE, Transform3D.IDENTITY, Color(0.7, 0.65, 0.6), 0.2)
	var faceted_arrays := _first_surface(faceted_box, materials)
	var faceted_colors: PackedColorArray = faceted_arrays[Mesh.ARRAY_COLOR]
	harness.check(
		faceted_colors[0].r > faceted_colors[6].r,
		"face variation subtly separates the top and underside"
	)
	for node in faceted_box.commit(materials):
		(node as MeshInstance3D).free()

	# Rocks opt into flat facet normals; foliage keeps the analytic smooth path.
	var flat_sphere := MeshBaker.new()
	flat_sphere.add_sphere("rock", 1.0, 3, 5, Transform3D.IDENTITY, Color.WHITE, true)
	var flat_arrays := _first_surface(flat_sphere, materials)
	var flat_vertices: PackedVector3Array = flat_arrays[Mesh.ARRAY_VERTEX]
	var flat_normals: PackedVector3Array = flat_arrays[Mesh.ARRAY_NORMAL]
	harness.check(
		flat_normals[0].distance_to(flat_normals[1]) < EPSILON,
		"a rock facet uses one planar normal"
	)
	harness.check_equals(
		_bad_windings(flat_vertices, flat_normals, Vector3.ZERO),
		0,
		"flat rock facets still face outwards"
	)
	for node in flat_sphere.commit(materials):
		(node as MeshInstance3D).free()


	# --- organic primitives (visual polish 16) --------------------------------
	# A limb is a bent tube, not a cylinder. Two segments with six sides give
	# 24 side triangles plus two six-triangle caps; the important part is that
	# a *bent* limb still emits outward-facing facets and caps.
	var limb_baker := MeshBaker.new()
	limb_baker.add_limb(
		"trunk",
		PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0.9, 0), Vector3(0, 1.8, 0)]),
		PackedFloat32Array([0.42, 0.24, 0.06]),
		6
	)
	harness.check_equals(
		limb_baker.get_triangle_count(), 36, "a two-segment limb is 36 triangles"
	)
	var limb_arrays := _first_surface(limb_baker, materials)
	harness.check_equals(
		_bad_windings(
			limb_arrays[Mesh.ARRAY_VERTEX],
			limb_arrays[Mesh.ARRAY_NORMAL],
			Vector3(0.0, 0.9, 0.0)
		),
		0,
		"limb facets and caps face outwards"
	)
	for node in limb_baker.commit(materials):
		(node as MeshInstance3D).free()

	# A foliage clump must not describe a sphere: its vertices are displaced by
	# a lobed function, which is what removes the identical-lollipop tree line.
	var clump_baker := MeshBaker.new()
	var clump_radii := Vector3(1.6, 1.0, 1.2)
	clump_baker.add_foliage_clump("leaf_mid", clump_radii, 4, 9, 42)
	harness.check_equals(
		clump_baker.get_triangle_count(), 54,
		"a foliage clump keeps the cheap sphere topology"
	)
	var clump_arrays := _first_surface(clump_baker, materials)
	harness.check_equals(
		_bad_windings(
			clump_arrays[Mesh.ARRAY_VERTEX],
			clump_arrays[Mesh.ARRAY_NORMAL],
			Vector3.ZERO
		),
		0,
		"every foliage facet faces outwards"
	)
	var lowest := INF
	var highest := 0.0
	for vertex in clump_arrays[Mesh.ARRAY_VERTEX]:
		var normalised := Vector3(
			vertex.x / clump_radii.x, vertex.y / clump_radii.y, vertex.z / clump_radii.z
		).length()
		lowest = minf(lowest, normalised)
		highest = maxf(highest, normalised)
	harness.check(
		highest - lowest > 0.05,
		"a foliage clump is lobed, not a sphere (radial spread %.3f)" % (highest - lowest)
	)
	for node in clump_baker.commit(materials):
		(node as MeshInstance3D).free()

	# A conifer whorl replaced the stack of cones: a ring of pointed needles
	# around a solid inner cone, closed above and below. The winding is resolved
	# per triangle, because the rim hangs below the ring and a naive fan would
	# turn the underside inside-out.
	var frond_baker := MeshBaker.new()
	frond_baker.add_frond_ring("pine", 2.0, 1.4, 0.5, 12, 7)
	harness.check_equals(
		frond_baker.get_triangle_count(), 72,
		"a frond whorl is six triangles per segment (four faces, top and underside)"
	)
	var frond_arrays := _first_surface(frond_baker, materials)
	harness.check_equals(
		_bad_windings(
			frond_arrays[Mesh.ARRAY_VERTEX],
			frond_arrays[Mesh.ARRAY_NORMAL],
			Vector3(0.0, 2.06, 0.0)
		),
		0,
		"every whorl facet faces outwards, including the underside"
	)
	harness.check_equals(
		_degenerate_triangles(frond_arrays[Mesh.ARRAY_VERTEX]), 0,
		"the whorl has no degenerate triangle"
	)
	# Alternating long and short needles are the whole point: a rim of equal
	# points is a disc, which is what made the old pines look like traffic cones.
	var rim_min := INF
	var rim_max := 0.0
	for vertex in frond_arrays[Mesh.ARRAY_VERTEX]:
		if vertex.y < 1.44 or vertex.y > 1.78:
			continue
		var radial := Vector2(vertex.x, vertex.z).length()
		rim_min = minf(rim_min, radial)
		rim_max = maxf(rim_max, radial)
	harness.check(
		rim_max - rim_min > 0.15,
		"the whorl rim alternates long and short needles (%.2f..%.2f)" % [rim_min, rim_max]
	)
	var frond_repeat := MeshBaker.new()
	frond_repeat.add_frond_ring("pine", 2.0, 1.4, 0.5, 12, 7)
	harness.check_equals(
		frond_repeat.get_triangle_count(), frond_baker.get_triangle_count(),
		"the same whorl seed rebuilds the same whorl"
	)
	for node in frond_baker.commit(materials):
		(node as MeshInstance3D).free()
	for node in frond_repeat.commit(materials):
		(node as MeshInstance3D).free()

	# A clump can carry its own vertical tint gradient. A crown built from dozens
	# of small masses reads as one volume only if the tops are lit and the
	# undersides fall away, and that has to survive the merge into one mesh.
	var shaded_clump := MeshBaker.new()
	shaded_clump.add_foliage_clump(
		"leaf_mid", Vector3(1.0, 1.6, 1.0), 3, 6, 11, Transform3D.IDENTITY,
		Color(0.8, 0.8, 0.8), false, 0.3
	)
	var shaded_arrays := _first_surface(shaded_clump, materials)
	var shaded_vertices: PackedVector3Array = shaded_arrays[Mesh.ARRAY_VERTEX]
	var shaded_colors: PackedColorArray = shaded_arrays[Mesh.ARRAY_COLOR]
	var top_color := 0.0
	var bottom_color := 1.0
	for index in shaded_vertices.size():
		if shaded_vertices[index].y > 1.0:
			top_color = maxf(top_color, shaded_colors[index].r)
		elif shaded_vertices[index].y < -1.0:
			bottom_color = minf(bottom_color, shaded_colors[index].r)
	harness.check(
		top_color > bottom_color + 0.1,
		"a shaded clump is lighter on top than underneath (%.2f > %.2f)"
		% [top_color, bottom_color]
	)
	for node in shaded_clump.commit(materials):
		(node as MeshInstance3D).free()

	# A rock uses a closed, ring-built profile with a buried foot and a clipped
	# crown. Seeded angular variation must never create a folded or degenerate
	# triangle, and every facet normal must agree with the visible winding.
	var rock_baker := MeshBaker.new()
	var rock_size := Vector3(1.8, 1.1, 1.4)
	rock_baker.add_rock("rock", rock_size, 41)
	harness.check(
		rock_baker.get_triangle_count() >= 60 and rock_baker.get_triangle_count() <= 80,
		"a faceted boulder costs 60–80 triangles, not a dense sculpt"
	)
	var rock_arrays := _first_surface(rock_baker, materials)
	var rock_vertices: PackedVector3Array = rock_arrays[Mesh.ARRAY_VERTEX]
	var rock_normals: PackedVector3Array = rock_arrays[Mesh.ARRAY_NORMAL]
	harness.check_equals(
		_bad_windings(rock_vertices, rock_normals, Vector3.ZERO),
		0,
		"all boulder facets and caps face outwards"
	)
	harness.check_equals(
		_degenerate_triangles(rock_vertices),
		0,
		"the bounded rock profile emits no zero-area triangles"
	)
	var lowest_rock_y := INF
	var highest_rock_y := -INF
	for vertex in rock_vertices:
		lowest_rock_y = minf(lowest_rock_y, vertex.y)
		highest_rock_y = maxf(highest_rock_y, vertex.y)
	harness.check(
		lowest_rock_y < -0.10 and highest_rock_y > 0.55,
		"the rock has an embedded base and a readable crown (%.2f…%.2f m)"
		% [lowest_rock_y, highest_rock_y]
	)
	var rock_tints: PackedColorArray = rock_arrays[Mesh.ARRAY_COLOR]
	var darkest_rock := 1.0
	var brightest_rock := 0.0
	for color in rock_tints:
		darkest_rock = minf(darkest_rock, color.r)
		brightest_rock = maxf(brightest_rock, color.r)
	harness.check(
		brightest_rock - darkest_rock > 0.05,
		"rock facets keep subtle tonal variation in the shared material"
	)

	var rock_signatures := {}
	for seed_value in [41, 42, 43]:
		var variant_baker := MeshBaker.new()
		variant_baker.add_rock("rock", rock_size, seed_value)
		var variant_arrays := _first_surface(variant_baker, materials)
		var variant_vertices: PackedVector3Array = variant_arrays[Mesh.ARRAY_VERTEX]
		var min_y := INF
		var max_y := -INF
		for vertex in variant_vertices:
			min_y = minf(min_y, vertex.y)
			max_y = maxf(max_y, vertex.y)
		rock_signatures["%.2f/%.2f" % [min_y, max_y]] = true
	harness.check(
		rock_signatures.size() >= 2,
		"different rock seeds form distinct proportions, not repeated boulders"
	)

	# A blade is two triangles with an upward normal: no alpha texture and no
	# crossed double-sided quad, which is where the old billboard grass came
	# from.
	var blade_baker := MeshBaker.new()
	blade_baker.add_blade("grass_blade", 0.6, 0.05, 0.01, Vector2(0.04, 0.12))
	harness.check_equals(blade_baker.get_triangle_count(), 2, "a blade is two triangles")
	var blade_arrays := _first_surface(blade_baker, materials)
	var blade_normals: PackedVector3Array = blade_arrays[Mesh.ARRAY_NORMAL]
	harness.check(
		blade_normals[0].y > 0.9,
		"a blade is lit like the meadow, so it never goes black from behind"
	)
	for node in blade_baker.commit(materials):
		(node as MeshInstance3D).free()

	# A stem or a low leaf hangs on `leaf_mid`, whose material culls back faces,
	# so the same quad is emitted twice with opposite windings. Grass does not
	# pay for that: its material is double-sided already.
	var leaf_baker := MeshBaker.new()
	leaf_baker.add_blade(
		"leaf_mid", 0.4, 0.03, 0.01, Vector2.ZERO, Transform3D.IDENTITY,
		Color.WHITE, 0.20, true
	)
	harness.check_equals(
		leaf_baker.get_triangle_count(), 4, "a culled leaf blade is emitted for both sides"
	)
	for node in leaf_baker.commit(materials):
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


static func _degenerate_triangles(vertices: PackedVector3Array) -> int:
	var degenerate := 0
	for index in range(0, vertices.size(), 3):
		var a := vertices[index]
		var b := vertices[index + 1]
		var c := vertices[index + 2]
		if (c - a).cross(b - a).length_squared() < EPSILON:
			degenerate += 1
	return degenerate


static func _first_surface(baker: MeshBaker, materials: VillageMaterials) -> Array:
	var baked: Array = baker.commit(materials)
	if baked.is_empty():
		return []
	var instance := baked[0] as MeshInstance3D
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	instance.free()
	return arrays
