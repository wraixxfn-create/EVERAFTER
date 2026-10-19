class_name TestGroundSurfaces
extends RefCounted
## Geometry checks for `GroundSurfaces`, runnable headless without a GPU.
##
## The paving is deliberately invisible to physics: the player walks on the
## terrain heightmap and the sheet is a 1–3 cm skin above it. That makes the two
## failure modes that matter testable as pure numbers:
## * a vertex that does not sample the terrain would float or sink;
## * a cell that ignores the building footprints would reappear under a wall.
## The suite also pins the triangle budget and the irregularity of the plaza
## rim, so a future change cannot quietly turn the square back into a disc or
## the pavement into a per-stone mesh.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("GroundSurfaces")

	var layout := VillageLayout.new(20261016, 79.5)
	var terrain := TerrainGenerator.new(160, 5.0, 20261016, layout)
	var surfaces := GroundSurfaces.new(layout, terrain, VillageMaterials.new())
	surfaces.build_geometry()

	# --- budget --------------------------------------------------------------
	harness.check(
		surfaces.get_triangle_count() > 1500,
		"the paving carries real detail (%d triangles)" % surfaces.get_triangle_count()
	)
	harness.check(
		surfaces.get_triangle_count() < 8000,
		"the paving stays a sheet, not a stone-by-stone model (%d triangles)"
		% surfaces.get_triangle_count()
	)
	harness.check(
		surfaces.get_vertex_count() == surfaces.get_triangle_count() / 2 * 6,
		"every quad emits six vertices (got %d for %d triangles)"
		% [surfaces.get_vertex_count(), surfaces.get_triangle_count()]
	)

	# --- grounding -----------------------------------------------------------
	# The sheet must sample the very height field the player collides with.
	var vertices := surfaces.get_vertices()
	var lowest := INF
	var highest := -INF
	for vertex in vertices:
		var ground := terrain.height_at(vertex.x, vertex.z)
		lowest = minf(lowest, vertex.y - ground)
		highest = maxf(highest, vertex.y - ground)
	harness.check(
		lowest > -0.002,
		"no paving vertex sinks into the terrain (worst %.3f m)" % lowest
	)
	harness.check(
		highest < 0.055,
		"no paving vertex floats above the terrain (worst %.3f m)" % highest
	)
	harness.check(
		highest - lowest < 0.06,
		"the sheet has a bounded thickness"
	)

	# --- the square is not a circle -----------------------------------------
	var minimum := INF
	var maximum := 0.0
	for index in 96:
		var angle := TAU * float(index) / 96.0
		var radius := surfaces.plaza_edge_radius(angle)
		minimum = minf(minimum, radius)
		maximum = maxf(maximum, radius)
	harness.check(
		maximum - minimum > 0.35,
		"the plaza rim wobbles instead of describing a compass circle (%.2f m)"
		% (maximum - minimum)
	)
	harness.check(
		minimum > 10.2 and maximum < 11.25,
		"the rim stays inside the kerb ring (%.2f..%.2f m)" % [minimum, maximum]
	)

	# --- paving never grows under a building --------------------------------
	var under_walls := 0
	for vertex in vertices:
		if surfaces.inside_structure(Vector2(vertex.x, vertex.z), -0.08):
			under_walls += 1
	harness.check_equals(
		under_walls, 0,
		"no paving vertex sits inside a foundation (got %d)" % under_walls
	)

	# --- every road keeps a compacted surface along its curve --------------
	# Only the low-lift vertices are road or verge: cobbles sit 2.6 cm up.
	var ground_vertices := PackedVector2Array()
	for vertex in vertices:
		if vertex.y <= terrain.height_at(vertex.x, vertex.z) + 0.021:
			ground_vertices.append(Vector2(vertex.x, vertex.z))
	var road_gaps := 0
	for road_index in layout.roads.size():
		var road := layout.roads[road_index]
		var length := VillageLayout.polyline_length(road)
		var distance := 14.0
		while distance < length - 4.0:
			var sample := VillageLayout.sample_polyline(road, distance)
			var point: Vector2 = sample.point
			if not surfaces.inside_structure(point, 1.2):
				var nearest := INF
				for flat in ground_vertices:
					nearest = minf(nearest, point.distance_to(flat))
				if nearest > 1.4:
					road_gaps += 1
			distance += 8.0
	harness.check_equals(
		road_gaps, 0, "every road has paving on its carriageway (%d gaps)" % road_gaps
	)

	# --- deterministic -------------------------------------------------------
	var again := GroundSurfaces.new(layout, terrain, VillageMaterials.new())
	again.build_geometry()
	harness.check_equals(
		again.get_triangle_count(), surfaces.get_triangle_count(),
		"the same seed builds the same paving budget"
	)
	harness.check(
		again.get_vertices()[0] == vertices[0]
		and again.get_vertices()[vertices.size() - 1] == vertices[vertices.size() - 1],
		"the same seed builds the same first and last vertex"
	)

	# --- materials -----------------------------------------------------------
	var keys := surfaces.get_material_keys()
	var materials := VillageMaterials.new()
	var unknown: PackedStringArray = []
	for key in keys:
		if not materials.has_color(key):
			unknown.append(key)
	harness.check_equals(
		unknown.size(), 0,
		"every paving material key exists in the palette (%s)" % ", ".join(unknown)
	)
	harness.check_equals(
		keys.size(), 2, "the pavement uses two shared materials, not thirty"
	)

	# --- kerbs ---------------------------------------------------------------
	var baker := MeshBaker.new()
	again.bake_kerbs(baker)
	harness.check(
		again.kerb_stone_count > 100,
		"the square and the roads are edged (%d stones)" % again.kerb_stone_count
	)
	harness.check(
		again.kerb_stone_count < 520,
		"edging is not a per-centimetre mesh (%d stones)" % again.kerb_stone_count
	)
	harness.check_equals(
		baker.get_triangle_count(), again.kerb_stone_count * 12,
		"each kerb stone is one box, merged into the shared prop mesh"
	)
	var keys_before := baker.get_material_keys_used()
	harness.check(
		keys_before.has("cobble"), "kerbs use the shared village cobble material"
	)
