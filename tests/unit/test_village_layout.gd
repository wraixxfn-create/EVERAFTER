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

	# --- visual polish 15: roads are smooth curves --------------------------
	# A road may bend, but it may not kink. The old generator walked 17 m and
	# then jumped sideways, so consecutive segments could meet at a visible
	# angle; the current curve is sampled every three metres and its heading
	# can only turn a few degrees per step.
	var worst_turn := 0.0
	var worst_excursion := 0.0
	for road in layout.roads:
		harness.check(
			road.size() >= 20,
			"a road is sampled as a dense curve (%d points)" % road.size()
		)
		for index in range(1, road.size() - 1):
			var before: Vector2 = road[index] - road[index - 1]
			var after: Vector2 = road[index + 1] - road[index]
			if before.length_squared() < 0.0001 or after.length_squared() < 0.0001:
				continue
			worst_turn = maxf(worst_turn, absf(before.angle_to(after)))
		var chord_start: Vector2 = road[0]
		var chord_end: Vector2 = road[road.size() - 1]
		var chord := chord_end - chord_start
		for point in road:
			var offset := point - chord_start
			var projection := offset.dot(chord) / maxf(chord.length_squared(), 0.0001)
			var closest := chord_start + chord * clampf(projection, 0.0, 1.0)
			worst_excursion = maxf(worst_excursion, point.distance_to(closest))
	harness.check(
		worst_turn < deg_to_rad(16.0),
		"no visible kink between road segments (worst turn %.1f degrees)"
		% rad_to_deg(worst_turn)
	)
	harness.check(
		worst_excursion > 0.9,
		"the roads meander instead of running as straight spokes (%.1f m)"
		% worst_excursion
	)
	harness.check(
		worst_excursion < 12.0, "a meander never loops back into the village"
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

	# --- visual polish 19: composition ---------------------------------------
	# The market row really is a row: three stalls, each far
	# enough from its neighbours to stand alone.
	var stalls := layout.get_placements_of_kind(VillageLayout.KIND_STALL)
	harness.check_equals(stalls.size(), 3, "the market row has three stalls")
	for stall_index in stalls.size():
		for other_index in range(stall_index + 1, stalls.size()):
			var gap := stalls[stall_index].position.distance_to(
				stalls[other_index].position)
			harness.check(
				gap > 4.4,
				"stalls %d and %d stand apart (%.2f m)" % [stall_index, other_index, gap]
			)

	# Every road mouth opens onto the square: the plot nearest
	# the plaza is a low wood yard, not a house gable.
	for road_index in layout.roads.size():
		var first_kind := _first_plot_kind(layout, road_index)
		harness.check_equals(
			first_kind, VillageLayout.KIND_LOGPILE,
			"road %d opens with a yard, not a gable" % road_index
		)

	# The arrival sightlines stay open: no tall tree stands
	# between a road's arrival points and the landmarks the
	# walk in should reveal. Re-derived from the public
	# placement list, like the doorway check above.
	var tall_on_sightline := 0
	for placement in layout.placements:
		if not VillageLayout.TREE_KINDS.has(placement.kind):
			continue
		if _blocks_an_arrival_sightline(layout, placement):
			tall_on_sightline += 1
	harness.check_equals(
		tall_on_sightline, 0, "no crown sits on an arrival sightline")

	# The pond-to-square axis stays open the same way.
	var tall_on_pond_axis := 0
	for placement in layout.placements:
		if not VillageLayout.TREE_KINDS.has(placement.kind):
			continue
		if _on_pond_vista(layout, placement.position):
			tall_on_pond_axis += 1
	harness.check_equals(
		tall_on_pond_axis, 0, "no crown sits on the pond vista axis")

	# The composed knots exist: the skyline sectors the random
	# passes leave empty carry deliberate tree groups.
	var knot_trees := 0
	for placement in layout.placements:
		if not VillageLayout.TREE_KINDS.has(placement.kind):
			continue
		var distance := placement.position.length()
		if distance < 26.0 or distance > 40.0:
			continue
		var azimuth := rad_to_deg(atan2(
			placement.position.x, placement.position.y))
		azimuth = fposmod(azimuth, 360.0)
		for knot in [100.0, 142.0, 222.0, 258.0, 335.0]:
			if absf(azimuth - knot) < 12.0:
				knot_trees += 1
				break
	harness.check(
		knot_trees >= 5,
		"the composed knots carry at least five trees (%d)" % knot_trees
	)

	# Street lighting survives the plot changes: every
	# road carries at least one lamp at its kerb.
	for road_index in layout.roads.size():
		var road_lamps := 0
		for lamp in layout.get_placements_of_kind(VillageLayout.KIND_LAMP):
			if _distance_to_polyline(
				lamp.position, layout.roads[road_index]) < 12.0:
				road_lamps += 1
		harness.check(
			road_lamps >= 1,
			"road %d keeps its street lamp" % road_index
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

## Kind of the road plot nearest the plaza on a given road.
## Re-derived from the public placement list: a plot belongs
## to the road whose centre line passes within 12 m of it,
## and stands beyond the ring of plaza landmarks (which are
## placed by bearing, not by road, and would otherwise win
## the "nearest" contest at every road mouth).
static func _first_plot_kind(layout: VillageLayout, road_index: int) -> String:
	var road: PackedVector2Array = layout.roads[road_index]
	var best_kind := ""
	var best_distance := INF
	for placement in layout.placements:
		if placement.kind != VillageLayout.KIND_HOUSE \
				and placement.kind != VillageLayout.KIND_LOGPILE:
			continue
		if placement.position.length() < 19.5:
			continue
		var nearest := Vector2.ZERO
		var nearest_distance := INF
		for index in road.size() - 1:
			var closest := _closest_on_segment(
				placement.position, road[index], road[index + 1])
			var distance := placement.position.distance_to(closest)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = closest
		if nearest_distance > 12.0:
			continue
		var travelled := _distance_along(road, nearest)
		if travelled < best_distance:
			best_distance = travelled
			best_kind = placement.kind
	return best_kind


## Length of a polyline up to a point known to lie on it.
static func _distance_along(road: PackedVector2Array, point: Vector2) -> float:
	var total := 0.0
	for index in road.size() - 1:
		var span := road[index + 1] - road[index]
		var length_sq := span.length_squared()
		if length_sq <= 0.0001:
			continue
		var t := clampf(
			(point - road[index]).dot(span) / length_sq, 0.0, 1.0)
		var closest := road[index] + span * t
		if point.distance_to(closest) < 0.5:
			return total + span.length() * t
		total += span.length()
	return total


static func _closest_on_segment(
	point: Vector2, start: Vector2, end: Vector2
) -> Vector2:
	var span := end - start
	var length_sq := span.length_squared()
	if length_sq <= 0.0001:
		return start
	var t := clampf((point - start).dot(span) / length_sq, 0.0, 1.0)
	return start + span * t


## True when a tall placement stands in one of the arrival
## sightlines: the segments from each road's arrival points
## to the plaza, the inn, the hall and its belfry. The
## belfry is re-derived from the hall placement exactly the
## way the architecture builds it, on the hall's local -X.
static func _blocks_an_arrival_sightline(
	layout: VillageLayout, placement: VillageLayout.Placement
) -> bool:
	var targets: Array[Vector2] = [Vector2.ZERO]
	var inn: VillageLayout.Placement = null
	var hall: VillageLayout.Placement = null
	for candidate in layout.placements:
		if candidate.kind == VillageLayout.KIND_INN and inn == null:
			inn = candidate
		if candidate.kind == VillageLayout.KIND_HALL and hall == null:
			hall = candidate
	if inn != null:
		targets.append(inn.position)
	if hall != null:
		targets.append(hall.position)
		var yaw := deg_to_rad(hall.rotation_deg)
		targets.append(hall.position + Vector2(
			-5.4 * cos(yaw), 5.4 * sin(yaw)))
	for road_index in layout.roads.size():
		for distance in VillageLayout.ARRIVAL_DISTANCES:
			var arrival := layout.point_on_road(road_index, distance)
			for target in targets:
				var clearance := (
					VillageLayout.ARRIVAL_CORRIDOR_HALF_WIDTH
					+ placement.footprint_radius * placement.scale
				)
				if _segment_near(
					placement.position, arrival, target, clearance
				):
					return true
	return false


## True when a point stands in the kept-open axis between
## the pond and the square.
static func _on_pond_vista(layout: VillageLayout, point: Vector2) -> bool:
	return _segment_near(
		point, layout.pond_center, Vector2.ZERO,
		VillageLayout.POND_VISTA_HALF_WIDTH
	)


## Shortest distance from a point to any segment of a polyline.
static func _distance_to_polyline(
	point: Vector2, road: PackedVector2Array
) -> float:
	var best := INF
	for index in road.size() - 1:
		var closest := _closest_on_segment(
			point, road[index], road[index + 1])
		best = minf(best, point.distance_to(closest))
	return best


## True when [param point] lies within [param half_width] of
## the segment [param start] -> [param end].
static func _segment_near(
	point: Vector2, start: Vector2, end: Vector2, half_width: float
) -> bool:
	var span := end - start
	var length_sq := span.length_squared()
	if length_sq <= 0.0001:
		return point.distance_to(start) < half_width
	var t := clampf((point - start).dot(span) / length_sq, 0.0, 1.0)
	return point.distance_to(start + span * t) < half_width
