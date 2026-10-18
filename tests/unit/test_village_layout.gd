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
	# A fence is 3 m long and excluded from ROAD_CLEARING_KINDS because it may
	# stand at the kerb. The paddock fence used to cut the road to the fields,
	# which made the fields unreachable for the NPC route graph (and for the
	# player): the layout now leaves a gate, so no fence may overlap a road.
	var fence_on_road := 0
	for fence in layout.get_placements_of_kind(VillageLayout.KIND_FENCE):
		var clearance: float = layout.distance_to_roads(fence.position)
		if clearance < VillageLayout.ROAD_WIDTH * 0.5 + 1.5:
			fence_on_road += 1
	harness.check_equals(
		fence_on_road, 0, "the paddock fence leaves the road to the fields open"
	)

	var overlapping := _count_overlaps(layout)
	harness.check_equals(overlapping, 0, "no two props overlap")

	# --- world detail ---------------------------------------------------------
	# The environmental-detail pass adds furnishings and yard clutter. What it
	# must never do is the thing the player feels first: fill a doorway. The
	# check re-derives the corridor rule from the public placement list, so it
	# stays honest even if the placer's internal guard changes.
	harness.check_equals(
		_count_blocked_doorways(layout), 0, "no prop stands in a doorway corridor"
	)
	harness.check(
		layout.get_placements_of_kind(VillageLayout.KIND_FLOWER_BOX).size() >= 4,
		"the village carries standing planters"
	)
	harness.check(
		layout.get_placements_of_kind(VillageLayout.KIND_BENCH).size() >= 3,
		"the village carries benches at the plaza and the pond"
	)
	harness.check(
		_count_furnished_houses(layout) >= 3,
		"yard clutter dresses at least three houses"
	)

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


## Independent re-derivation of the doorway corridor rule: every prop whose
## radius reaches into the door strip of a house, inn or hall counts once.
static func _count_blocked_doorways(layout: VillageLayout) -> int:
	var blocked := 0
	var door_kinds := [
		VillageLayout.KIND_HOUSE, VillageLayout.KIND_INN, VillageLayout.KIND_HALL
	]
	for host in layout.placements:
		if not door_kinds.has(host.kind):
			continue
		var yaw := deg_to_rad(host.rotation_deg)
		var reach := host.footprint_radius * host.scale + VillageLayout.DOOR_CORRIDOR_REACH
		for other in layout.placements:
			if other == host:
				continue
			var delta := other.position - host.position
			var local_z := delta.x * sin(yaw) + delta.y * cos(yaw)
			if local_z <= 0.0 or local_z > reach:
				continue
			var local_x := delta.x * cos(yaw) - delta.y * sin(yaw)
			var half_width := (
				VillageLayout.DOOR_CORRIDOR_HALF_WIDTH
				+ other.footprint_radius * other.scale * 0.5
			)
			if absf(local_x) < half_width:
				blocked += 1
	return blocked


## How many houses carry at least one piece of yard clutter within a few metres.
static func _count_furnished_houses(layout: VillageLayout) -> int:
	var clutter_kinds := [
		VillageLayout.KIND_CRATE, VillageLayout.KIND_BARREL,
		VillageLayout.KIND_LOGPILE, VillageLayout.KIND_FLOWER_BOX
	]
	var furnished := 0
	for house in layout.get_placements_of_kind(VillageLayout.KIND_HOUSE):
		var reach := house.footprint_radius * house.scale + 3.5
		for placement in layout.placements:
			if not clutter_kinds.has(placement.kind):
				continue
			if placement.position.distance_to(house.position) <= reach:
				furnished += 1
				break
	return furnished
