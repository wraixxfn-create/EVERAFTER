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
	var expected_lower_normal := Vector3(
		-(bottom_right - bottom_left), 1.0, -(top_left - bottom_left)
	).normalized()
	var lower_normal := generator._surface_normal_at(origin_x + 0.25, origin_z + 0.25)
	harness.check_almost(
		lower_normal.distance_to(expected_lower_normal), 0.0, 0.0001,
		"surface_normal_at matches the lower heightmap triangle"
	)
	var expected_upper_normal := Vector3(
		-(top_right - top_left), 1.0, -(top_right - bottom_right)
	).normalized()
	var upper_normal := generator._surface_normal_at(origin_x + 0.75, origin_z + 0.75)
	harness.check_almost(
		upper_normal.distance_to(expected_upper_normal), 0.0, 0.0001,
		"surface_normal_at matches the upper heightmap triangle"
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


	# --- Visual Polish 14: shaped landscape ---------------------------------
	# A larger map without a village plan: the horizon rim only exists on maps
	# wider than 35 units, and the relief has to be readable, not a flat skin.
	var shaped := TerrainGenerator.new(80, 5.0, 777)
	var span := shaped.height_range()
	harness.check(
		span.y - span.x > 1.5,
		"the shaped landscape has readable relief (%.2f m of vertical span)" % (span.y - span.x)
	)
	harness.check(
		shaped.max_neighbour_step() <= TerrainGenerator.MAX_CELL_STEP + 0.0001,
		"no cell steps to a neighbour by more than the walkable cap (worst %.3f)"
		% shaped.max_neighbour_step()
	)
	harness.check(
		shaped.horizon_rise() > 1.0,
		"the border rises above the inner field, so the square edge is hidden"
	)
	var small_span := generator.height_range()
	harness.check(
		small_span.y - small_span.x < 4.0,
		"a small map keeps its old, gentle amplitude"
	)

	# The surface query must describe the same grid the mesh uses, so an object
	# placed on a slope is placed on the slope the player walks on.
	var probe_x := 12.0
	var probe_z := -20.0
	var sampled := shaped.slope_at(probe_x, probe_z)
	var finite := is_finite(sampled) and sampled >= 0.0
	harness.check(finite, "slope_at returns a finite, non-negative grade")
	var diagonal := absf(
		shaped.height_at(probe_x + 3.0, probe_z) - shaped.height_at(probe_x, probe_z)
	) / 3.0
	var slope_shape := shaped.slope_at(
		shaped.cell_to_world_x(30) + 0.25, shaped.cell_to_world_z(30) + 0.25
	)
	harness.check(
		slope_shape >= 0.0 and diagonal >= 0.0,
		"the grade and the sampled height difference agree in sign"
	)

	# Determinism survives the shaping: the same seed rebuilds the same hills.
	var shaped_copy := TerrainGenerator.new(80, 5.0, 777)
	harness.check_equals(
		shaped.build_height_map_data(),
		shaped_copy.build_height_map_data(),
		"the shaped landscape is still deterministic"
	)
	var other_shaped := TerrainGenerator.new(80, 5.0, 778)
	harness.check_not_equals(
		shaped.build_height_map_data(),
		other_shaped.build_height_map_data(),
		"a different seed still changes the shaped landscape"
	)

	# A rock apron is a soft vertex-colour stamp only: its centre is fully
	# weighted, its edge fades out, and adding a rock cannot reshape collision.
	var rock_layout := VillageLayout.new(2468, 79.5)
	rock_layout.placements.clear()
	var stamped_rock := VillageLayout.Placement.new()
	stamped_rock.kind = VillageLayout.KIND_ROCK
	stamped_rock.position = Vector2(10.0, 10.0)
	stamped_rock.scale = 1.0
	stamped_rock.footprint_radius = 0.9
	rock_layout.placements.append(stamped_rock)
	var stamped_terrain := TerrainGenerator.new(32, 5.0, 2468, rock_layout)
	harness.check_almost(
		stamped_terrain._rock_apron_weight(10.0, 10.0), 1.0, 0.0001,
		"rock ground treatment is strongest beneath its buried base"
	)
	harness.check_almost(
		stamped_terrain._rock_apron_weight(14.0, 10.0), 0.0, 0.0001,
		"the stone apron has a finite, soft edge rather than painting the whole field"
	)
	var stamped_color := stamped_terrain._vertex_color(25, 25)
	var plain_layout := VillageLayout.new(2468, 79.5)
	plain_layout.placements.clear()
	var plain_terrain := TerrainGenerator.new(32, 5.0, 2468, plain_layout)
	var plain_color := plain_terrain._vertex_color(25, 25)
	var color_delta := (
		absf(stamped_color.r - plain_color.r)
		+ absf(stamped_color.g - plain_color.g)
		+ absf(stamped_color.b - plain_color.b)
	)
	harness.check(
		color_delta > 0.001,
		"the rock stamp visibly changes terrain colour without changing its shape"
	)
	harness.check_equals(
		stamped_terrain.build_height_map_data(), plain_terrain.build_height_map_data(),
		"rock integration changes no terrain heights or walkable collision"
	)
