class_name TestVillageLayout
extends RefCounted
## Checks for `VillageLayout`: determinism, the shape of the road network, the
## placement rules the player relies on (no house in the middle of a road, no
## two buildings on top of each other) and the ground weights the terrain uses.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("VillageLayout")

	var layout := VillageLayout.new(20261016, 79.5)
	var same := VillageLayout.new(20261016, 79.5)
	var other := VillageLayout.new(4242, 79.5)

	# --- determinism ---------------------------------------------------------
	harness.check_equals(
		layout.get_placement_count(),
		same.get_placement_count(),
		"the same seed places the same number of props"
	)
	harness.check(layout.get_placement_count() > 100, "the village is populated")
	var identical := true
	for index in mini(layout.get_placement_count(), 60):
		var left: VillageLayout.Placement = layout.placements[index]
		var right: VillageLayout.Placement = same.placements[index]
		if left.kind != right.kind or left.position != right.position:
			identical = false
			break
	harness.check(identical, "the same seed rebuilds the identical village")
	harness.check(
		_signature(layout) != _signature(other), "a different seed changes the village"
	)

	# --- landmarks -----------------------------------------------------------
	harness.check_equals(layout.roads.size(), 3, "three roads leave the plaza")
	var wells := layout.get_placements_of_kind(VillageLayout.KIND_WELL)
	harness.check_equals(wells.size(), 1, "the plaza has exactly one well")
	if wells.size() == 1:
		harness.check_almost(
			wells[0].position.length(), 0.0, 0.001, "the well stands at the centre"
		)
	harness.check_equals(
		layout.get_placements_of_kind(VillageLayout.KIND_INN).size(), 1, "there is one inn"
	)
	harness.check_equals(
		layout.get_placements_of_kind(VillageLayout.KIND_HALL).size(),
		1,
		"there is one community building"
	)
	harness.check(
		layout.get_placements_of_kind(VillageLayout.KIND_HOUSE).size() >= 6,
		"the village has several houses"
	)
	harness.check(
		layout.get_placements_of_kind(VillageLayout.KIND_TREE_PINE).size()
			+ layout.get_placements_of_kind(VillageLayout.KIND_TREE_OAK).size()
			+ layout.get_placements_of_kind(VillageLayout.KIND_TREE_BIRCH).size()
			> 100,
		"there is a forest, not a handful of trees"
	)

	# --- houses differ from each other ---------------------------------------
	var widths := {}
	for house in layout.get_placements_of_kind(VillageLayout.KIND_HOUSE):
		widths[house.variant] = true
	harness.check(
		widths.size() >= 2, "houses use more than one variant, so silhouettes differ"
	)

	# --- placement rules -----------------------------------------------------
	var outside := 0
	var on_road := 0
	for placement in layout.placements:
		if absf(placement.position.x) > layout.half_extent - 1.0:
			outside += 1
		if absf(placement.position.y) > layout.half_extent - 1.0:
			outside += 1
		if VillageLayout.ROAD_CLEARING_KINDS.has(placement.kind):
			var clearance: float = layout.distance_to_roads(placement.position)
			if clearance < VillageLayout.ROAD_WIDTH * 0.5:
				on_road += 1
	harness.check_equals(outside, 0, "nothing is placed outside the terrain")
	harness.check_equals(on_road, 0, "no structure stands on a road")

	var overlapping := _count_overlaps(layout)
	harness.check_equals(overlapping, 0, "no two props overlap")

	# --- ground weights ------------------------------------------------------
	harness.check_almost(
		layout.flatten_weight(0.0, 0.0), 1.0, 0.001, "the plaza centre is level ground"
	)
	harness.check(
		layout.flatten_weight(layout.half_extent * 0.9, layout.half_extent * 0.9) < 0.2,
		"open country is not flattened"
	)
	harness.check_almost(
		layout.plaza_weight(0.0, 0.0), 1.0, 0.001, "the plaza weight peaks at the centre"
	)
	harness.check_almost(
		layout.plaza_weight(60.0, 60.0), 0.0, 0.001, "the plaza weight is zero far away"
	)
	harness.check(
		layout.road_distance(0.0, 0.0) > VillageLayout.ROAD_WIDTH,
		"the plaza centre is not on a road"
	)
	harness.check(
		layout.built_ground_coverage(6.0) > 0.02,
		"some of the map is built ground (paths and plaza)"
	)

	# --- roads and the pond --------------------------------------------------
	var first_road: PackedVector2Array = layout.roads[0]
	harness.check(first_road.size() >= 3, "a road is a polyline, not a single segment")
	harness.check(
		first_road[0].length() < VillageLayout.PLAZA_RADIUS,
		"roads start at the edge of the plaza"
	)
	harness.check(
		first_road[first_road.size() - 1].length() > layout.half_extent * 0.7,
		"roads reach towards the border"
	)
	harness.check_almost(
		layout.point_on_road(0, 0.0).length(),
		first_road[0].length(),
		0.001,
		"point_on_road starts at the first waypoint"
	)
	harness.check(
		layout.point_on_road(0, 1.0e6).length() > layout.half_extent * 0.7,
		"point_on_road clamps to the end of the road"
	)
	harness.check(
		layout.terrain_offset(layout.pond_center.x, layout.pond_center.y) < 0.0,
		"the pond basin is carved below the surrounding ground"
	)
	harness.check_almost(layout.terrain_offset(0.0, 0.0), 0.0, 0.0001, "no basin at the plaza")

	# --- areas ---------------------------------------------------------------
	var areas := layout.build_area_registry()
	harness.check(areas.get_area_count() >= 6, "the layout names its regions")
	harness.check_equals(
		areas.area_at(Vector2.ZERO), "Piazza del Pozzo", "the plaza centre is named"
	)
	harness.check(
		not areas.area_at(layout.pond_center).is_empty(), "the pond is named"
	)


static func _signature(layout: VillageLayout) -> String:
	var parts: PackedStringArray = []
	for index in mini(layout.get_placement_count(), 40):
		var placement: VillageLayout.Placement = layout.placements[index]
		parts.append("%s@%.3f,%.3f" % [placement.kind, placement.position.x, placement.position.y])
	return "|".join(parts)


static func _count_overlaps(layout: VillageLayout) -> int:
	var overlaps := 0
	var count := layout.placements.size()
	for i in count:
		var left: VillageLayout.Placement = layout.placements[i]
		for j in range(i + 1, count):
			var right: VillageLayout.Placement = layout.placements[j]
			# The rejection rule uses the *scaled* footprint, with a 0.92 factor
			# and a small tolerance for floating point noise.
			var needed := (
				left.footprint_radius * left.scale + right.footprint_radius * right.scale
			) * 0.92
			if left.position.distance_to(right.position) < needed - 0.0001:
				overlaps += 1
	return overlaps
