class_name TestPavedSurfaces
extends RefCounted
## Integration checks for the paved surfaces added in visual polish 15.
##
## Kept in its own module so the main world suite stays under the linter's file
## length limit. The checks need the live scene: real generated textures, real
## merged meshes and the terrain heightmap the player actually collides with.

const MAX_PAVING_TRIANGLES := 9000


## Visual polish 15: the paved surfaces are real geometry, not a colour patch.
## They have to follow the terrain the player collides with, stay inside the
## triangle budget, and remain invisible to physics (the heightmap is still the
## only thing the capsule touches). The materials are also checked here because
## the procedural textures are generated at boot: a missing texture would show
## as an untextured grey sheet rather than as an error.
static func check_paved_surfaces(harness: TestHarness, world: Node3D) -> void:
	harness.suite("PavedSurfaces")
	var terrain: TerrainGenerator = world.get_terrain()
	var village := world.get_node_or_null("Village/Village") as Node3D
	harness.check(terrain != null and village != null, "world exposes terrain and village")
	if terrain == null or village == null:
		return
	var paving := village.get_node_or_null("Paving") as Node3D
	harness.check(paving != null, "the village has a Paving node")
	if paving == null:
		return
	var meshes := 0
	var triangles := 0
	var worst_below := INF
	var worst_above := -INF
	var missing_uvs := 0
	var untextured := 0
	var colliders := 0
	for child in paving.get_children():
		if child is CollisionShape3D or child is StaticBody3D:
			colliders += 1
		if not (child is MeshInstance3D):
			continue
		meshes += 1
		var mesh_instance := child as MeshInstance3D
		triangles += _mesh_triangles(mesh_instance.mesh)
		var material := mesh_instance.material_override as StandardMaterial3D
		if material == null or material.albedo_texture == null:
			untextured += 1
		else:
			harness.check(
				material.normal_enabled, "the paving material carries a relief normal map"
			)
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var uvs = arrays[Mesh.ARRAY_TEX_UV]
			if uvs == null or (uvs as PackedVector2Array).is_empty():
				missing_uvs += 1
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var ground := terrain.height_at(vertex.x, vertex.z)
				worst_below = minf(worst_below, vertex.y - ground)
				worst_above = maxf(worst_above, vertex.y - ground)
	harness.check(meshes >= 2, "the pavement is a handful of merged meshes (%d)" % meshes)
	harness.check_equals(
		colliders, 0, "paving adds no colliders: the terrain heightmap stays authoritative"
	)
	harness.check(
		triangles > 1000 and triangles < 9000,
		"the paving stays inside its triangle budget (%d triangles)" % triangles
	)
	harness.check_equals(untextured, 0, "every paving mesh got its procedural texture")
	harness.check_equals(missing_uvs, 0, "every paving surface carries UVs")
	harness.check(
		worst_below > -0.01,
		"no paving vertex sinks into the ground (worst %.3f m)" % worst_below
	)
	harness.check(
		worst_above < 0.055,
		"no paving vertex floats above the ground (worst %.3f m)" % worst_above
	)


static func _mesh_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface in mesh.get_surface_count():
		var vertices = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		if vertices == null:
			continue
		total += (vertices as PackedVector3Array).size() / 3
	return total
