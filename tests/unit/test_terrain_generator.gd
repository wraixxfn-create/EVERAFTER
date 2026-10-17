class_name TestTerrainGenerator
extends RefCounted
## Checks for `TerrainGenerator`: determinism, the flat plaza, the agreement
## between `height_at`, the height grid and the physics heightmap, and the
## winding of the generated mesh.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("TerrainGenerator")

	var generator := TerrainGenerator.new(32, 5.0, 1234)
	var same_seed := TerrainGenerator.new(32, 5.0, 1234)
	var other_seed := TerrainGenerator.new(32, 5.0, 4321)

	# --- pure geometry of the grid -------------------------------------------
	harness.check_equals(generator.size_cells, 32, "size is kept")
	harness.check_equals(generator.get_vertex_count(), 32 * 32, "one vertex per grid point")
	harness.check_equals(generator.get_triangle_count(), 31 * 31 * 2, "two triangles per cell")
	harness.check_almost(generator.get_extent(), 31.0, 0.0001, "32 cells span 31 units")
	harness.check_almost(
		generator.get_half_extent(), 15.5, 0.0001, "the grid is centred on the origin"
	)
	harness.check_almost(generator.cell_to_world_x(0), -15.5, 0.0001, "first column is at -15.5")
	harness.check_almost(generator.cell_to_world_z(31), 15.5, 0.0001, "last row is at +15.5")

	# --- determinism ---------------------------------------------------------
	harness.check_equals(
		generator.build_height_map_data(),
		same_seed.build_height_map_data(),
		"the same seed rebuilds the same heights"
	)
	harness.check_not_equals(
		generator.build_height_map_data(),
		other_seed.build_height_map_data(),
		"a different seed changes the heights"
	)
	harness.check_equals(
		generator.build_height_map_data().size(), 32 * 32, "height data has one value per grid point"
	)

	# --- flat plaza ----------------------------------------------------------
	harness.check_almost(generator.height_at(0.0, 0.0), 0.0, 0.0001, "the plaza centre is at y = 0")
	harness.check_almost(generator.height_at(5.0, -7.0), 0.0, 0.0001, "the whole plaza is flat")
	harness.check_almost(generator.grid_height(16, 16), 0.0, 0.0001, "the central grid point is flat")

	# --- height_at agrees with the grid and with the physics heightmap --------
	var data := generator.build_height_map_data()
	for iz in range(0, 32, 7):
		for ix in range(0, 32, 5):
			var world_x := generator.cell_to_world_x(ix)
			var world_z := generator.cell_to_world_z(iz)
			harness.check_almost(
				generator.height_at(world_x, world_z),
				generator.grid_height(ix, iz),
				0.0001,
				"height_at matches the grid at cell (%d, %d)" % [ix, iz]
			)
			harness.check_almost(
				data[iz * 32 + ix],
				generator.grid_height(ix, iz),
				0.0001,
				"height map data uses index iz * width + ix at (%d, %d)" % [ix, iz]
			)

	# --- piecewise planar interpolation (same triangles as HeightMapShape3D) --
	var ix := 10
	var iz := 12
	var bottom_left := generator.grid_height(ix, iz)
	var bottom_right := generator.grid_height(ix + 1, iz)
	var top_left := generator.grid_height(ix, iz + 1)
	var top_right := generator.grid_height(ix + 1, iz + 1)
	var origin_x := generator.cell_to_world_x(ix)
	var origin_z := generator.cell_to_world_z(iz)
	harness.check_almost(
		generator.height_at(origin_x + 1.0 / 3.0, origin_z + 1.0 / 3.0),
		(bottom_left + bottom_right + top_left) / 3.0,
		0.0001,
		"the lower triangle interpolates over (bottom_left, top_left, bottom_right)"
	)
	harness.check_almost(
		generator.height_at(origin_x + 2.0 / 3.0, origin_z + 2.0 / 3.0),
		(top_left + top_right + bottom_right) / 3.0,
		0.0001,
		"the upper triangle interpolates over (top_left, top_right, bottom_right)"
	)
	harness.check_almost(
		generator.height_at(origin_x + 0.3, origin_z + 0.7),
		generator.height_at(origin_x + 0.3 + 0.0001, origin_z + 0.7 - 0.0001),
		0.001,
		"the surface is continuous across the cell diagonal"
	)

	# --- bounds --------------------------------------------------------------
	harness.check_almost(
		generator.height_at(-1000.0, 0.0),
		generator.height_at(-15.5, 0.0),
		0.0001,
		"sampling outside the terrain is clamped to the border"
	)
	harness.check_almost(
		generator.height_at(900.0, 900.0),
		generator.height_at(15.5, 15.5),
		0.0001,
		"sampling far outside is clamped on both axes"
	)

	# --- build products ------------------------------------------------------
	var shape := generator.build_collision_shape()
	harness.check_equals(shape.map_width, 32, "collision width matches the grid")
	harness.check_equals(shape.map_depth, 32, "collision depth matches the grid")
	harness.check_equals(shape.map_data.size(), 32 * 32, "collision data matches the grid")
	harness.check_equals(shape.map_data, data, "collision data is the generated height grid")

	var material := generator.build_material()
	harness.check(material.vertex_color_use_as_albedo, "vertex colours drive the terrain albedo")

	var mesh := generator.build_mesh()
	harness.check(mesh != null, "build_mesh returns a mesh")
	if mesh == null:
		return
	harness.check_equals(mesh.get_surface_count(), 1, "the terrain is a single surface")
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty():
		harness.skip("surface_get_arrays returned nothing (no rendering backend available)")
		return
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if vertices.is_empty() or normals.is_empty() or colors.is_empty():
		harness.skip("mesh arrays are not readable in this rendering backend")
		return
	harness.check_equals(
		vertices.size(), generator.get_vertex_count(), "mesh has one vertex per point"
	)
	harness.check_equals(normals.size(), vertices.size(), "mesh has one normal per vertex")
	harness.check_equals(colors.size(), vertices.size(), "every terrain vertex has a surface colour")
	var colour_range := Vector3(INF, INF, INF)
	var colour_high := Vector3(-INF, -INF, -INF)
	for color in colors:
		colour_range.x = minf(colour_range.x, color.r)
		colour_range.y = minf(colour_range.y, color.g)
		colour_range.z = minf(colour_range.z, color.b)
		colour_high.x = maxf(colour_high.x, color.r)
		colour_high.y = maxf(colour_high.y, color.g)
		colour_high.z = maxf(colour_high.z, color.b)
	harness.check(
		(colour_high - colour_range).length() > 0.05,
		"the terrain retains deterministic colour mottling instead of a flat fill"
	)
	var upward := 0
	for normal in normals:
		if normal.y > 0.0:
			upward += 1
	harness.check_equals(upward, normals.size(), "every terrain normal points up (winding is correct)")
	harness.check_almost(vertices[0].x, -15.5, 0.0001, "the first vertex is the grid origin")
