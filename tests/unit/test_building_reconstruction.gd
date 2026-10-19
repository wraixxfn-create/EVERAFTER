class_name TestBuildingReconstruction
extends RefCounted
## Structural regressions, independent of lighting and of the world scene.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("BuildingReconstruction")
	var materials := VillageMaterials.new()
	var factory := BuildingFactory.new(materials, 17)
	_check_profiles(harness, materials)
	for index in 5:
		var placement := _placement(index)
		var baker := MeshBaker.new()
		factory.bake_structure(baker, placement)
		var instances := baker.commit(materials)
		print(
			(
				"[Architecture] variant=%d triangles=%d meshes=%d"
				% [index, baker.get_triangle_count(), instances.size()]
			)
		)
		var bad := 0
		var degenerates := 0
		var finite := true
		for instance in instances:
			var mesh: Mesh = instance.mesh
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for vertex in vertices:
				finite = finite and vertex.is_finite()
			for offset in range(0, vertices.size(), 3):
				var wound := (vertices[offset + 2] - vertices[offset]).cross(
					vertices[offset + 1] - vertices[offset]
				)
				if wound.length_squared() < 0.000000001:
					degenerates += 1
				elif wound.normalized().dot(normals[offset]) < 0.98:
					bad += 1
		harness.check(finite, "variant %d: finite vertices" % index)
		harness.check_equals(bad, 0, "variant %d: all faces have outward winding" % index)
		harness.check_equals(degenerates, 0, "variant %d: no zero-area triangles" % index)
		harness.check(baker.get_triangle_count() < 12000, "variant %d: triangle budget" % index)
		harness.check(instances.size() <= 12, "variant %d: merged by shared material" % index)
		_check_apertures(harness, instances, index)
		if index == 4:
			_check_bell_clearance(harness, instances)
		var normal_bounds := _bounds(instances)
		placement.scale = 0.85
		var scaled := MeshBaker.new()
		factory.bake_structure(scaled, placement)
		var scaled_instances := scaled.commit(materials)
		var scaled_bounds := _bounds(scaled_instances)
		harness.check(
			(
				scaled_bounds.position.is_equal_approx(normal_bounds.position * 0.85)
				and scaled_bounds.size.is_equal_approx(normal_bounds.size * 0.85)
			),
			"variant %d: every component scales exactly once" % index
		)
		_free_meshes(scaled_instances)
		_free_meshes(instances)
		var node := factory.build_structure(placement)
		harness.check_equals(String(node.name), placement.id, "placement ID is still the root name")
		harness.check(
			node.get_node_or_null("Collision") is StaticBody3D, "Collision path preserved"
		)
		harness.check_equals(
			node.get_node("Collision").get_child_count(),
			2 if index >= 3 else 1,
			"original collision shape count preserved"
		)
		node.free()


static func _check_profiles(harness: TestHarness, materials: VillageMaterials) -> void:
	# The old box builder emitted six rectangles through its centre. Bounds
	# alone did not catch it: every vertex must be a real boundary corner.
	var box := MeshBaker.new()
	box.add_box("stone", Vector3(2.0, 4.0, 6.0))
	var box_instances := box.commit(materials)
	var box_arrays: Array = box_instances[0].mesh.surface_get_arrays(0)
	var box_vertices: PackedVector3Array = box_arrays[Mesh.ARRAY_VERTEX]
	var boundary_corners := true
	for vertex in box_vertices:
		boundary_corners = (
			boundary_corners
			and is_equal_approx(absf(vertex.x), 1.0)
			and is_equal_approx(absf(vertex.y), 2.0)
			and is_equal_approx(absf(vertex.z), 3.0)
		)
	harness.check(boundary_corners, "boxes have six boundary faces, not three centre sheets")
	_free_meshes(box_instances)
	for mirrored in [false, true]:
		var profile := PackedVector2Array(
			[Vector2(0, 0), Vector2(2, 0), Vector2(2.1, 0.06), Vector2(2.1, 0.14), Vector2(0, 0.14)]
		)
		if mirrored:
			for index in profile.size():
				profile[index].x *= -1.0
		var baker := MeshBaker.new()
		baker.add_profile("roof_tile", profile, 3.0)
		var instances := baker.commit(materials)
		var arrays: Array = instances[0].mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var edges := {}
		for index in range(0, vertices.size(), 3):
			for edge in 3:
				var a := str(vertices[index + edge])
				var b := str(vertices[index + (edge + 1) % 3])
				var key := a + ":" + b if a < b else b + ":" + a
				edges[key] = int(edges.get(key, 0)) + 1
		var closed := true
		for count in edges.values():
			closed = closed and count == 2
		harness.check(closed, "roof sections are closed manifolds, including mirrored end caps")
		_free_meshes(instances)


static func _check_apertures(harness: TestHarness, instances: Array, index: int) -> void:
	var front_z := 1.7 if index == 2 else (2.7 if index >= 3 else 2.0)
	if index == 1:
		front_z = 1.91
	var window_x := [1.386, 1.323, 1.827, 2.52, 3.35][index] as float
	var window_y := 2.0 if index == 4 else 1.6
	harness.check(
		not _wall_in_aperture(instances, Vector3(window_x, window_y, front_z)),
		"variant %d: window is in an actual wall aperture" % index
	)
	harness.check(
		not _wall_in_aperture(instances, Vector3(0.0, 1.5, front_z)),
		"variant %d: doorway has depth, not a door pasted onto a wall" % index
	)
	harness.check(
		_wall_in_aperture(instances, Vector3(2.6 if index >= 3 else 0.65, 2.3, front_z)),
		"variant %d: surrounding wall is still solid" % index
	)


static func _wall_in_aperture(instances: Array, point: Vector3) -> bool:
	for instance in instances:
		if not (
			String(instance.name).trim_prefix("Baked_")
			in ["wall_cream", "wall_ochre", "wall_pale", "wall_ash", "stone"]
		):
			continue
		var arrays: Array = instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in range(0, vertices.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(
				point + Vector3.BACK * 0.5,
				Vector3.FORWARD,
				vertices[index],
				vertices[index + 1],
				vertices[index + 2]
			)
			if hit is Vector3 and absf(hit.z - point.z) < 0.24:
				return true
	return false


static func _check_bell_clearance(harness: TestHarness, instances: Array) -> void:
	var nave_top := -INF
	var bell_bottom := INF
	for instance in instances:
		var arrays: Array = instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if instance.name == "Baked_roof_slate" and vertex.x > -3.0:
				nave_top = maxf(nave_top, vertex.y)
			if (
				instance.name == "Baked_iron"
				and absf(vertex.x + 5.4) < 0.55
				and absf(vertex.z) < 0.55
				and vertex.y > 6.0
			):
				bell_bottom = minf(bell_bottom, vertex.y)
	harness.check(
		is_finite(nave_top) and is_finite(bell_bottom) and bell_bottom > nave_top + 0.1,
		"the nave roof cannot intersect the suspended bell"
	)


static func _bounds(instances: Array) -> AABB:
	var bounds: AABB = instances[0].mesh.get_aabb()
	for instance in instances:
		bounds = bounds.merge(instance.mesh.get_aabb())
	return bounds


static func _free_meshes(instances: Array) -> void:
	for instance in instances:
		instance.free()


static func _placement(index: int) -> VillageLayout.Placement:
	var placement := VillageLayout.Placement.new()
	placement.id = "reconstruction_%d" % index
	placement.kind = VillageLayout.KIND_HOUSE
	placement.variant = mini(index, 2)
	placement.scale = 1.0
	if index == 3:
		placement.kind = VillageLayout.KIND_INN
	elif index == 4:
		placement.kind = VillageLayout.KIND_HALL
	return placement
