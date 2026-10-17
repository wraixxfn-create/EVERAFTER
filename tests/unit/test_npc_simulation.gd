class_name TestNpcSimulation
extends RefCounted
## Behaviour tests for `NpcSimulationSystem`: unique IDs, individual state,
## needs evolving with simulated time, schedule-following routines, hunger and
## sleep, continuous movement, unreachable destinations and determinism.
##
## Everything runs on a synthetic flat world with a straight road, so the test
## needs neither a scene nor a GPU nor the real village layout.


class Fixture extends RefCounted:
	var system: NpcSimulationSystem = null
	var loop: SimulationLoop = null


class BrokenGraph extends NpcRouteGraph:
	## Claims every place is reachable, but never returns a path: exactly the
	## failure mode `_travel_to` must survive without teleporting.

	func _init() -> void:
		pass

	func is_place_reachable(_place_id: String) -> bool:
		return true

	func find_path(_from: Vector2, _to_place_id: String) -> PackedVector2Array:
		return PackedVector2Array()

	func get_unreachable_place_ids() -> PackedStringArray:
		return PackedStringArray()

	func get_node_count() -> int:
		return 0


static func run_tests(harness: TestHarness) -> void:
	harness.suite("NpcSimulation")
	_test_identity_and_individuality(harness)
	_test_needs_evolve(harness)
	_test_work_schedule(harness)
	_test_night_sleep(harness)
	_test_hunger_and_food(harness)
	_test_unreachable_destination(harness)
	_test_movement_continuity(harness)
	_test_determinism(harness)


static func _test_identity_and_individuality(harness: TestHarness) -> void:
	var fixture := _build_fixture(8 * 60, 9 * 60, 17 * 60)
	var system := fixture.system
	var records := system.get_records()
	harness.check_equals(records.size(), 10, "the fixture simulates ten inhabitants")
	var seen := {}
	var unique := true
	for record in records:
		if seen.has(record.id):
			unique = false
		seen[record.id] = true
		harness.check(record.position.is_finite(), "the start position is finite")
		harness.check(not record.home_place_id.is_empty(), "every record has a home")
	harness.check_equals(
			system.get_record(record.id), record, "records are addressable by id"
		)
	harness.check(unique, "no NPC id is duplicated")
	harness.check(records[0].needs != records[1].needs, "needs are not shared")
	var original_other := records[1].needs.hunger
	records[0].needs.hunger = 77.0
	harness.check_almost(
		records[1].needs.hunger, original_other, 0.0001, "changing one NPC does not change another"
	)


static func _test_needs_evolve(harness: TestHarness) -> void:
	var fixture := _build_fixture(9 * 60, 9 * 60, 17 * 60)
	var before: Array[Dictionary] = []
	for record in fixture.system.get_records():
		before.append(record.needs.to_dict())
	fixture.loop.run_ticks(30)
	var changed := 0
	for index in fixture.system.get_records().size():
		var record := fixture.system.get_records()[index]
		var old: Dictionary = before[index]
		if not is_equal_approx(record.needs.energy, float(old["energy"])) \
				or not is_equal_approx(record.needs.hunger, float(old["hunger"])):
			changed += 1
		harness.check(
			record.needs.energy >= NpcNeeds.MIN_VALUE
			and record.needs.energy <= NpcNeeds.MAX_VALUE,
			"energy stays in range"
		)
		harness.check(
			record.needs.hunger >= NpcNeeds.MIN_VALUE
			and record.needs.hunger <= NpcNeeds.MAX_VALUE,
			"hunger stays in range"
		)
	harness.check(changed > 0, "needs evolve when simulated time advances")
	harness.check_equals(
		fixture.system.get_last_tick(), fixture.loop.clock.tick, "the system knows the last tick"
	)


static func _test_work_schedule(harness: TestHarness) -> void:
	var fixture := _build_fixture(9 * 60, 9 * 60, 17 * 60)
	for record in fixture.system.get_records():
		record.needs.hunger = 10.0
		record.needs.energy = 90.0
	fixture.loop.run_ticks(200)
	var working := 0
	var blocked := 0
	for record in fixture.system.get_records():
		if record.activity == NpcRecord.Activity.WORKING:
			working += 1
		if record.activity == NpcRecord.Activity.BLOCKED:
			blocked += 1
	harness.check(working >= 8, "most inhabitants are working during their shift (got %d)" % working)
	harness.check_equals(blocked, 0, "nobody is blocked in a connected fixture")

	var off_duty := _build_fixture(20 * 60, 9 * 60, 17 * 60)
	off_duty.loop.run_ticks(5)
	var working_off := 0
	for record in off_duty.system.get_records():
		if record.activity == NpcRecord.Activity.WORKING:
			working_off += 1
	harness.check_equals(working_off, 0, "nobody works outside the scheduled hours")


static func _test_night_sleep(harness: TestHarness) -> void:
	var fixture := _build_fixture(23 * 60, 9 * 60, 17 * 60)
	fixture.loop.run_ticks(10)
	var sleeping := 0
	for record in fixture.system.get_records():
		if record.activity == NpcRecord.Activity.SLEEPING:
			sleeping += 1
	harness.check_equals(sleeping, 10, "every inhabitant sleeps at home at night")
	var before := fixture.system.get_records()[0].needs.energy
	fixture.loop.run_ticks(30)
	harness.check(
		fixture.system.get_records()[0].needs.energy > before,
		"sleeping restores energy"
	)


static func _test_hunger_and_food(harness: TestHarness) -> void:
	var fixture := _build_fixture(10 * 60, 0, 0)
	var hungry := fixture.system.get_records()[0]
	hungry.needs.hunger = 95.0
	var saw_eating := false
	var saw_food_walk := false
	for _tick in 200:
		fixture.loop.run_ticks(1)
		if hungry.activity == NpcRecord.Activity.EATING:
			saw_eating = true
			break
		if hungry.activity == NpcRecord.Activity.WALKING \
				and hungry.goal == NpcRecord.Goal.SEEK_FOOD:
			saw_food_walk = true
	harness.check(saw_food_walk, "a hungry NPC walks to a food place")
	harness.check(saw_eating, "a hungry NPC reaches the food and eats")
	if saw_eating:
		harness.check_equals(
			hungry.current_place_id, "food_inn", "the NPC eats at the food place"
		)
		var hunger_at_eating := hungry.needs.hunger
		fixture.loop.run_ticks(NpcSimulationSystem.EAT_DURATION_TICKS)
		harness.check(
			hungry.needs.hunger < hunger_at_eating - 20.0, "eating reduces hunger"
		)
	harness.check(
		hungry.needs.hunger >= NpcNeeds.MIN_VALUE, "hunger never goes below zero"
	)


static func _test_unreachable_destination(harness: TestHarness) -> void:
	var fixture := _build_fixture(10 * 60, 0, 0, true, true)
	var hungry := fixture.system.get_records()[0]
	hungry.needs.hunger = 95.0
	var start_position := hungry.position
	# The initialization may have left the record in a short idle pause after a
	# failed free-time trip; let that pause expire so the urgent need is decided.
	fixture.loop.run_ticks(5)
	harness.check_equals(
		hungry.activity, NpcRecord.Activity.BLOCKED, "an empty path blocks the NPC"
	)
	harness.check_equals(hungry.goal, NpcRecord.Goal.BLOCKED, "the blocked goal is explicit")
	harness.check_equals(
		hungry.position, start_position, "the blocked NPC does not teleport"
	)
	harness.check(hungry.blocked_ticks > 0, "the blocked state has a recovery countdown")
	for _tick in 5:
		fixture.loop.run_ticks(1)
		harness.check_equals(
			hungry.position, start_position, "the NPC never teleports while recovering"
		)


static func _test_movement_continuity(harness: TestHarness) -> void:
	var fixture := _build_fixture(7 * 60, 9 * 60, 17 * 60)
	var moved := 0.0
	var valid := true
	for _tick in 300:
		var before: Array[Vector2] = []
		for record in fixture.system.get_records():
			before.append(record.position)
		fixture.loop.run_ticks(1)
		for index in fixture.system.get_records().size():
			var record := fixture.system.get_records()[index]
			if not record.position.is_finite():
				valid = false
			var step := before[index].distance_to(record.position)
			moved += step
			if step > NpcSimulationSystem.WALK_DISTANCE_PER_TICK + 0.001:
				valid = false
				harness.check(
					false,
					"%s moved %.3f in one tick (max %.3f)"
					% [record.id, step, NpcSimulationSystem.WALK_DISTANCE_PER_TICK]
				)
	harness.check(valid, "every NPC moves at most the walking speed per tick")
	harness.check(moved > 0.0, "the population actually moves over time")


static func _test_determinism(harness: TestHarness) -> void:
	var first := _build_fixture(8 * 60, 9 * 60, 17 * 60)
	var second := _build_fixture(8 * 60, 9 * 60, 17 * 60)
	first.loop.run_ticks(240)
	second.loop.run_ticks(240)
	harness.check_equals(
		var_to_str(first.system.to_dict()),
		var_to_str(second.system.to_dict()),
		"identical initial states produce identical worlds after 240 ticks"
	)


# --- fixture -----------------------------------------------------------------


static func _build_fixture(
	start_tick: int,
	work_start: int,
	work_end: int,
	with_food: bool = true,
	use_broken_graph: bool = false
) -> Fixture:
	var records := NpcRoster.build(10)
	for record in records:
		record.work_start_minute = work_start
		record.work_end_minute = work_end
		record.needs.hunger = minf(record.needs.hunger, 20.0)
	var places := _build_places(with_food)
	var roads: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-25, 0), Vector2(25, 0)])
	]
	var obstacles: Array[NpcRouteGraph.Obstacle] = [
		NpcRouteGraph.Obstacle.new("decorative_rock", Vector2(0, 12), 2.0)
	]
	var graph: NpcRouteGraph = BrokenGraph.new() if use_broken_graph \
		else NpcRouteGraph.new(places, roads, obstacles)
	var system := NpcSimulationSystem.new(records, places, graph)
	system.initialize(start_tick)
	var loop := SimulationLoop.new()
	loop.tick_seconds = 0.05
	loop.max_steps_per_frame = 64
	loop.clock.tick = maxi(start_tick - 1, 0)
	loop.register_system(system)
	var fixture := Fixture.new()
	fixture.system = system
	fixture.loop = loop
	return fixture


static func _build_places(with_food: bool) -> NpcPlaceRegistry:
	var registry := NpcPlaceRegistry.new()
	for index in 10:
		registry.add(
			"home_%03d" % (index + 1),
			"Casa %d" % (index + 1),
			NpcPlace.Kind.HOME,
			Vector2(-18.0 + float(index) * 1.4, 3.0),
			0,
			0,
			true
		)
	registry.add("work_field", "Campi", NpcPlace.Kind.WORK, Vector2(-20, 0))
	registry.add("work_inn", "Locanda", NpcPlace.Kind.WORK, Vector2(-15, 0))
	registry.add("work_market", "Mercato", NpcPlace.Kind.WORK, Vector2(-10, 0))
	registry.add("work_hall", "Sala", NpcPlace.Kind.WORK, Vector2(-5, 0))
	registry.add("work_forge", "Fucina", NpcPlace.Kind.WORK, Vector2(0, 0))
	registry.add("work_garden", "Giardino", NpcPlace.Kind.WORK, Vector2(5, 0))
	registry.add("work_pond", "Stagno", NpcPlace.Kind.WORK, Vector2(10, 0))
	registry.add("work_workshop", "Bottega", NpcPlace.Kind.WORK, Vector2(15, 0))
	registry.add(
		"food_inn",
		"Cibo",
		NpcPlace.Kind.FOOD,
		Vector2(2, 0),
		0,
		0,
		with_food
	)
	registry.add(
		"social_plaza", "Piazza", NpcPlace.Kind.SOCIAL, Vector2(0, -3)
	)
	registry.add(
		"rest_inn", "Riposo", NpcPlace.Kind.REST, Vector2(4, 3), 0, 0
	)
	return registry
