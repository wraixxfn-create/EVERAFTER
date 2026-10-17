class_name TestVillageNpcPlaces
extends RefCounted
## Tests the bridge between the 3D village plan and the pure-data NPC world:
## home assignment, anchor clearance, workplace coverage, opening hours and
## the reachability of every place an inhabitant is asked to walk to.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("VillageNpcPlaces")
	var layout := VillageLayout.new(7, 63.5)
	var records := NpcRoster.build(10)
	_test_registry_valid(harness, layout, records)
	_test_home_assignment(harness, layout, records)
	_test_work_places(harness, records)
	_test_opening_hours(harness, layout, records)
	_test_obstacles_deterministic(harness, layout)
	_test_reachability(harness, layout, records)


static func _test_registry_valid(
	harness: TestHarness, layout: VillageLayout, records: Array[NpcRecord]
) -> void:
	var places := VillageNpcPlaces.build(layout, records)
	harness.check_equals(places.validate().size(), 0, "the generated registry is valid")
	harness.check_equals(places.get_count(), 24, "fourteen shared places plus ten homes")
	var kinds := {
		NpcPlace.Kind.HOME: 0,
		NpcPlace.Kind.WORK: 0,
		NpcPlace.Kind.FOOD: 0,
		NpcPlace.Kind.SOCIAL: 0,
		NpcPlace.Kind.REST: 0,
		NpcPlace.Kind.LEISURE: 0,
	}
	for place in places.all_places():
		kinds[place.kind] = int(kinds.get(place.kind, 0)) + 1
		harness.check(place.position.is_finite(), "place '%s' has a finite position" % place.id)
		harness.check(
			absf(place.position.x) <= layout.half_extent
			and absf(place.position.y) <= layout.half_extent,
			"place '%s' stays inside the world" % place.id
		)
	harness.check_equals(kinds[NpcPlace.Kind.HOME], 10, "ten homes")
	harness.check_equals(kinds[NpcPlace.Kind.WORK], 8, "eight workplaces")
	harness.check(kinds[NpcPlace.Kind.FOOD] >= 2, "at least two food places")
	harness.check(kinds[NpcPlace.Kind.SOCIAL] >= 1, "at least one social place")
	harness.check(kinds[NpcPlace.Kind.REST] >= 1, "at least one rest place")


static func _test_home_assignment(
	harness: TestHarness, layout: VillageLayout, records: Array[NpcRecord]
) -> void:
	var places := VillageNpcPlaces.build(layout, records)
	var homes := places.home_places()
	harness.check_equals(homes.size(), records.size(), "one home per inhabitant")
	var positions := {}
	for index in records.size():
		var expected_id := "home_%03d" % (index + 1)
		var home := places.get_place(expected_id)
		harness.check(home != null, "home '%s' exists" % expected_id)
		if home == null:
			continue
		harness.check_equals(home.kind, NpcPlace.Kind.HOME, "home kind is HOME")
		var first_name := records[index].display_name.get_slice(" ", 0)
		harness.check(
			home.display_name.contains(first_name),
			"home '%s' names its inhabitant" % expected_id
		)
		harness.check(not positions.has(home.position), "home positions are distinct")
		positions[home.position] = expected_id
	# Rebuilding must assign the same house to the same record.
	var again := VillageNpcPlaces.build(VillageLayout.new(7, 63.5), records)
	harness.check_equals(
		again.get_place("home_003").position,
		places.get_place("home_003").position,
		"home assignment is deterministic"
	)
	# Door anchors must not sit inside an obstacle or in the pond.
	var obstacles := VillageNpcPlaces.build_obstacles(layout)
	for home in homes:
		var clearance := INF
		for obstacle in obstacles:
			clearance = minf(
				clearance, home.position.distance_to(obstacle.position) - obstacle.radius
			)
		harness.check(clearance >= 0.3, "home '%s' is walkable (clearance %.2f)" % [
			home.id, clearance
		])
		harness.check(
			home.position.distance_to(layout.pond_center) >= layout.pond_radius + 0.5,
			"home '%s' is not in the water" % home.id
		)


static func _test_work_places(harness: TestHarness, records: Array[NpcRecord]) -> void:
	var places := VillageNpcPlaces.build(VillageLayout.new(7, 63.5), records)
	for record in records:
		harness.check(
			places.has_place(record.work_place_id),
			"%s has a workplace (%s)" % [record.display_name, record.work_place_id]
		)
		var place := places.get_place(record.work_place_id)
		if place == null:
			continue
		harness.check_equals(
			place.kind, NpcPlace.Kind.WORK, "%s works in a WORK place" % record.display_name
		)
		harness.check(
			record.work_start_minute >= 0
			and record.work_start_minute < SimulationClock.MINUTES_PER_DAY,
			"%s starts within the day" % record.display_name
		)
		harness.check(
			record.work_end_minute > record.work_start_minute
			and record.work_end_minute <= SimulationClock.MINUTES_PER_DAY,
			"%s ends after starting" % record.display_name
		)
		harness.check(
			record.is_within_work_hours(record.work_start_minute),
			"%s is on duty at shift start" % record.display_name
		)


static func _test_opening_hours(
	harness: TestHarness, layout: VillageLayout, records: Array[NpcRecord]
) -> void:
	var places := VillageNpcPlaces.build(layout, records)
	var noon := 12 * 60
	var night := 3 * 60
	var food := places.find_food_place(noon)
	harness.check(food != null, "food is available at midday")
	harness.check(food == null or food.serves_food, "the midday food place serves food")
	harness.check(
		places.find_open_place(NpcPlace.Kind.FOOD, night) == null,
		"no public kitchen is open in the middle of the night"
	)
	var preferred := places.find_food_place(noon, "food_market")
	harness.check(preferred != null, "the preferred food place is honoured")
	if preferred != null:
		harness.check_equals(preferred.id, "food_market", "the market feeds at noon")
	var inn := places.get_place("food_inn")
	harness.check(
		not inn.is_open(10 * 60) and inn.is_open(12 * 60),
		"the inn opens for lunch"
	)
	var social := places.find_social_place(16 * 60)
	harness.check(social != null, "a social place is open in the afternoon")
	var rest := places.find_rest_place(23 * 60)
	harness.check(rest != null, "a rest place is available at night")


static func _test_obstacles_deterministic(harness: TestHarness, layout: VillageLayout) -> void:
	var first := VillageNpcPlaces.build_obstacles(layout)
	var second := VillageNpcPlaces.build_obstacles(VillageLayout.new(7, 63.5))
	harness.check_equals(first.size(), second.size(), "obstacle count is deterministic")
	harness.check(first.size() > 20, "the village produces a meaningful obstacle set")
	var names_match := true
	var radii_positive := true
	var seen := {}
	var unique := true
	for index in first.size():
		if first[index].label != second[index].label:
			names_match = false
		if first[index].radius <= 0.0:
			radii_positive = false
		if seen.has(first[index].label):
			unique = false
		seen[first[index].label] = true
	harness.check(names_match, "obstacle order and labels are deterministic")
	harness.check(radii_positive, "every obstacle has a positive radius")
	harness.check(unique, "obstacle labels are unique")
	harness.check(seen.has("pond_water"), "the pond is an obstacle")


static func _test_reachability(
	harness: TestHarness, layout: VillageLayout, records: Array[NpcRecord]
) -> void:
	var places := VillageNpcPlaces.build(layout, records)
	var obstacles := VillageNpcPlaces.build_obstacles(layout)
	var graph := NpcRouteGraph.new(places, layout.roads, obstacles)
	harness.check(graph.get_node_count() > 0, "the route graph owns walkable nodes")
	harness.check_equals(
		graph.get_unreachable_place_ids().size(),
		0,
		"every place is reachable: %s" % [graph.get_unreachable_place_ids()]
	)
	for record in records:
		harness.check(
			graph.is_place_reachable(record.work_place_id),
			"%s can walk to work" % record.display_name
		)
	for home in places.home_places():
		harness.check(graph.is_place_reachable(home.id), "%s is reachable" % home.id)
	var path := graph.find_path(
		places.get_place("home_001").position, "work_field"
	)
	harness.check(path.size() >= 2, "a path from home 1 to the fields exists")
	harness.check_equals(
		graph.find_path(places.get_place("home_001").position, "work_field"),
		path,
		"paths are deterministic"
	)
