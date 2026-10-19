class_name TestBuildingArchitecture
extends RefCounted
## Regression checks for the architectural geometry and its collision envelope.
## These assertions are engine-side and headless: they inspect baked vertices,
## not screenshots, so they catch material splits and closed-off basins directly.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("BuildingArchitecture")
	var materials := VillageMaterials.new()
	var buildings := BuildingFactory.new(materials, 17)

	# A gable facade is its own wall material, while the overhanging verge stays
	# roof material. Splitting the end faces must not reverse any triangle.
	var roof := MeshBaker.new()
	roof.add_prism(
		"roof_tile",
		4.0,
		2.0,
		3.0,
		Transform3D.IDENTITY,
		Color.WHITE,
		"wall_cream",
		3.2,
		Color(0.96, 0.94, 0.9)
	)
	harness.check_equals(
		roof.get_triangle_count(), 10, "an inset gable keeps roof verges and two roof slopes"
	)
	harness.check_equals(
		roof.get_material_keys_used(),
		PackedStringArray(["roof_tile", "wall_cream"]),
		"gable and roof use existing shared materials"
	)
	var bad_windings := 0
	for instance in roof.commit(materials):
		var mesh := (instance as MeshInstance3D).mesh
		for surface_index in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			bad_windings += _bad_windings(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL])
		(instance as MeshInstance3D).free()
	harness.check_equals(bad_windings, 0, "split gable faces preserve outward winding")

	# The simple two-storey and long-house bodies have different footprints; the
	# collision boxes now follow the model rather than reusing one size for all.
	var long_house := _placement(VillageLayout.KIND_HOUSE, 2)
	var long_shapes := buildings.colliders_for(long_house)
	var long_box := (long_shapes[0] as CollisionShape3D).shape as BoxShape3D
	harness.check_almost(long_box.size.x, 6.0, 0.001, "long-house collider covers its width")
	harness.check_almost(long_box.size.z, 3.8, 0.001, "long-house collider follows its depth")
	for shape in long_shapes:
		(shape as CollisionShape3D).free()

	var upper_house := _placement(VillageLayout.KIND_HOUSE, 1)
	var upper_shapes := buildings.colliders_for(upper_house)
	var upper_box := (upper_shapes[0] as CollisionShape3D).shape as BoxShape3D
	harness.check_almost(
		upper_box.size.y, 4.62, 0.001, "two-storey wall collider reaches the eaves"
	)
	for shape in upper_shapes:
		(shape as CollisionShape3D).free()

	var hall_shapes := buildings.colliders_for(_placement(VillageLayout.KIND_HALL, 0))
	var tower_collider := hall_shapes[1] as CollisionShape3D
	var tower_box := tower_collider.shape as BoxShape3D
	harness.check_almost(tower_box.size.y, 8.0, 0.001, "bell tower collider matches its wall")
	harness.check_almost(
		tower_collider.position.y, 4.0, 0.001, "bell tower collider stays grounded"
	)
	for shape in hall_shapes:
		(shape as CollisionShape3D).free()

	# A front window close to the doorway is shifted to clear the casing,
	# shutter and planter; the rear window remains centered.
	var front_window := buildings._surface_details.window_location(0, 2, 4.4, 1.0, 1.98, 0.95, 1.85)
	var rear_window := buildings._surface_details.window_location(1, 2, 4.4, 1.0, 1.98, 0.95, 1.85)
	harness.check(
		front_window.y > 0.0 and absf(front_window.x) >= 1.35,
		"low front window clears the centred entrance"
	)
	harness.check(
		rear_window.y < 0.0 and is_zero_approx(rear_window.x),
		"the rear opening keeps its ordinary placement"
	)

	var steps := MeshBaker.new()
	buildings._surface_details.add_door_steps(steps, 2.2, 5.4, 1.0, 0.5)
	var lowest_step_vertex := INF
	var highest_step_vertex := -INF
	for instance in steps.commit(materials):
		var mesh := (instance as MeshInstance3D).mesh
		for surface_index in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				lowest_step_vertex = minf(lowest_step_vertex, vertex.y)
				highest_step_vertex = maxf(highest_step_vertex, vertex.y)
		(instance as MeshInstance3D).free()
	harness.check_almost(lowest_step_vertex, 0.0, 0.001, "entrance steps meet the ground")
	harness.check_almost(highest_step_vertex, 0.5, 0.001, "upper step meets the hall plinth")

	# The old well had a solid dark cap directly over the water. No stone vertex
	# may now sit above the water inside the basin's open inner radius.
	var well := _placement(VillageLayout.KIND_WELL, 0)
	var well_baker := MeshBaker.new()
	buildings.bake_structure(well_baker, well)
	harness.check(
		well_baker.get_material_keys_used().has("water"), "well still includes its water surface"
	)
	var central_cover_vertices := 0
	for instance in well_baker.commit(materials):
		if instance.name in ["Baked_stone", "Baked_stone_dark"]:
			var mesh := (instance as MeshInstance3D).mesh
			for surface_index in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					if vertex.y > 0.76 and Vector2(vertex.x, vertex.z).length() < 0.93:
						central_cover_vertices += 1
		(instance as MeshInstance3D).free()
	harness.check_equals(central_cover_vertices, 0, "stone coping leaves the well aperture open")

	var well_shapes := buildings.colliders_for(well)
	var well_cylinder := (well_shapes[0] as CollisionShape3D).shape as CylinderShape3D
	harness.check_almost(well_cylinder.radius, 1.36, 0.001, "well collider covers the outer coping")
	for shape in well_shapes:
		(shape as CollisionShape3D).free()

	_check_roof_architecture(harness, materials, well_baker)


static func _check_roof_architecture(
	harness: TestHarness, materials: VillageMaterials, well_baker: MeshBaker
) -> void:
	var roof_kit := RoofArchitecture.new()
	var clamped := roof_kit.sanitize_spec(
		{"span": 0.2, "length": 0.1, "rise": 0.01, "overhang_eave": 9.0, "roof_key": "roof_tile"}
	)
	harness.check(
		float(clamped.span) >= 1.2 and float(clamped.length) >= 1.2,
		"degenerate roof dimensions are clamped to safe minimum span and length"
	)
	harness.check(
		float(clamped.rise) >= float(clamped.span) * 0.5 * RoofArchitecture.MIN_PITCH_RATIO,
		"degenerate roof rise is clamped to coherent minimum slope pitch"
	)

	for roof_key in ["roof_tile", "roof_shingle", "roof_slate"]:
		var baker := MeshBaker.new()
		var spec := {
			"span": 4.2,
			"length": 4.8,
			"eave_y": 2.6,
			"rise": 1.65,
			"overhang_eave": 0.34,
			"overhang_front": 0.3,
			"overhang_back": 0.3,
			"roof_key": roof_key,
			"wall_key": "wall_cream",
		}
		roof_kit.build_pitched_roof(baker, Transform3D.IDENTITY, Transform3D.IDENTITY, spec)
		roof_kit.build_gable_dormer(
			baker, Transform3D.IDENTITY, Transform3D.IDENTITY, spec, 1.0, 0.0, 0.96
		)
		roof_kit.build_chimney(
			baker, Transform3D.IDENTITY, Transform3D.IDENTITY, spec, Vector2(-1.1, -0.9), 4.8, 2
		)
		for key in baker.get_material_keys_used():
			harness.check(
				materials.has_color(key),
				"%s roof kit only uses valid VillageMaterials palette keys (%s)" % [roof_key, key]
			)
		var max_x := 0.0
		var max_y := 0.0
		var bad := 0
		for instance in baker.commit(materials):
			var mesh := (instance as MeshInstance3D).mesh
			for surface_index in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface_index)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in verts:
					max_x = maxf(max_x, absf(v.x))
					max_y = maxf(max_y, v.y)
				bad += _bad_windings(verts, arrays[Mesh.ARRAY_NORMAL])
			(instance as MeshInstance3D).free()
		harness.check_equals(bad, 0, "%s roof kit preserves outward triangle winding" % roof_key)
		harness.check(
			max_x > 2.35 and max_y > 4.75,
			"%s roof overhangs walls and crowns chimney above ridge" % roof_key
		)

	var spire_baker := MeshBaker.new()
	roof_kit.build_belfry_spire(
		spire_baker, Transform3D.IDENTITY, Transform3D.IDENTITY, 9.5, 2.46, 2.35
	)
	var spire_bad := 0
	for instance in spire_baker.commit(materials):
		var mesh := (instance as MeshInstance3D).mesh
		for surface_index in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			spire_bad += _bad_windings(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL])
		(instance as MeshInstance3D).free()
	harness.check_equals(spire_bad, 0, "tiered belfry spire preserves outward triangle winding")

	var low_gable_shingle := 0
	for instance in well_baker.commit(materials):
		if instance.name == "Baked_roof_shingle":
			var mesh := (instance as MeshInstance3D).mesh
			for surface_index in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface_index)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in verts:
					if absf(v.z) < 0.22 and v.y < 2.95:
						low_gable_shingle += 1
		(instance as MeshInstance3D).free()
	harness.check_equals(
		low_gable_shingle, 0, "well roof uses an open king-post truss without a solid shingle gable"
	)


static func _placement(kind: String, variant: int) -> VillageLayout.Placement:
	var placement := VillageLayout.Placement.new()
	placement.id = "architecture_test"
	placement.kind = kind
	placement.variant = variant
	placement.scale = 1.0
	return placement


static func _bad_windings(vertices: PackedVector3Array, normals: PackedVector3Array) -> int:
	var bad := 0
	for index in range(0, vertices.size(), 3):
		var a := vertices[index]
		var b := vertices[index + 1]
		var c := vertices[index + 2]
		var wound := (c - a).cross(b - a).normalized()
		if wound.dot(normals[index]) < 0.5:
			bad += 1
	return bad
