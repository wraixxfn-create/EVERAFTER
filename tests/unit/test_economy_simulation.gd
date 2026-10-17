class_name TestEconomySimulation
extends RefCounted
## Behaviour tests for `EconomySystem` integrated with `NpcSimulationSystem`
## and `SimulationLoop`:
## * production depends on actual work done and workplace prerequisites;
## * merchant facilitates exchanges without creating wealth out of nothing;
## * food consumption is linked to inhabitants and scarcity affects needs
##   without mortality;
## * multi-day simulation is deterministic, repeatable and never produces
##   negative resource counts.


class EconomyFixture extends RefCounted:
	var loop: SimulationLoop = null
	var npc_system: NpcSimulationSystem = null
	var economy: EconomySystem = null


static func run_tests(harness: TestHarness) -> void:
	harness.suite("EconomySimulation")
	_test_production_by_profession(harness)
	_test_inactive_or_blocked_worker_does_not_produce(harness)
	_test_merchant_facilitates_trade_without_creating_wealth(harness)
	_test_food_consumption_linked_to_inhabitants(harness)
	_test_food_scarcity_affects_needs_without_mortality(harness)
	_test_multi_day_determinism_and_non_negativity(harness)


static func _test_production_by_profession(harness: TestHarness) -> void:
	var fixture := _build_fixture(8 * 60, 10, 24, 12, 10, 60)
	for record in fixture.npc_system.get_records():
		record.work_start_minute = 8 * 60
		record.work_end_minute = 16 * 60
		record.needs.hunger = 10.0
		record.needs.energy = 95.0

	fixture.loop.run_ticks(240)

	var food_produced := fixture.economy.get_production(ResourceType.FOOD)
	var wood_produced := fixture.economy.get_production(ResourceType.WOOD)
	var stone_produced := fixture.economy.get_production(ResourceType.STONE)

	harness.check(
		food_produced > 0,
		"farmers/foragers/fishers/bakers produce Food during work shift (got %d)"
		% food_produced
	)
	harness.check(
		wood_produced > 0,
		"woodcutter produces Wood during work shift (got %d)" % wood_produced
	)
	harness.check(
		stone_produced > 0,
		"quarry worker produces Stone during work shift (got %d)" % stone_produced
	)


static func _test_inactive_or_blocked_worker_does_not_produce(harness: TestHarness) -> void:
	var night_fixture := _build_fixture(23 * 60, 10, 24, 12, 10, 60)
	night_fixture.loop.run_ticks(120)
	harness.check_equals(
		night_fixture.economy.get_production(ResourceType.FOOD),
		0,
		"no Food is produced while inhabitants are sleeping"
	)
	harness.check_equals(
		night_fixture.economy.get_production(ResourceType.WOOD),
		0,
		"no Wood is produced while inhabitants are sleeping"
	)
	harness.check_equals(
		night_fixture.economy.get_production(ResourceType.STONE),
		0,
		"no Stone is produced while inhabitants are sleeping"
	)

	var prereq_fixture := _build_fixture(8 * 60, 10, 24, 12, 10, 60)
	for record in prereq_fixture.npc_system.get_records():
		record.work_start_minute = 8 * 60
		record.work_end_minute = 16 * 60
		record.needs.hunger = 10.0
		record.needs.energy = 95.0
	prereq_fixture.economy.set_workplace_ready("work_workshop", false)
	prereq_fixture.economy.set_workplace_ready("work_forge", false)
	prereq_fixture.loop.run_ticks(200)
	harness.check_equals(
		prereq_fixture.economy.get_production(ResourceType.WOOD),
		0,
		"woodcutter produces 0 Wood when workshop prerequisite is not ready"
	)
	harness.check_equals(
		prereq_fixture.economy.get_production(ResourceType.STONE),
		0,
		"quarry worker produces 0 Stone when extraction prerequisite is not ready"
	)
	harness.check(
		prereq_fixture.economy.get_production(ResourceType.FOOD) > 0,
		"ready workplaces (fields/pond/garden) still produce Food normally"
	)

	var tired_fixture := _build_fixture(8 * 60, 1, 24, 12, 10, 60)
	var farmer := tired_fixture.npc_system.get_records()[0]
	farmer.work_start_minute = 8 * 60
	farmer.work_end_minute = 16 * 60
	farmer.needs.energy = 2.0
	tired_fixture.loop.run_ticks(90)
	harness.check_equals(
		tired_fixture.economy.get_production(ResourceType.FOOD),
		0,
		"an exhausted farmer (energy 2) rests instead of producing as if working"
	)


static func _test_merchant_facilitates_trade_without_creating_wealth(
	harness: TestHarness
) -> void:
	var fixture := _build_fixture(9 * 60, 3, 10, 22, 10, 60)
	var records := fixture.npc_system.get_records()
	records[0].work_start_minute = 20 * 60
	records[0].work_end_minute = 21 * 60
	records[1].work_start_minute = 20 * 60
	records[1].work_end_minute = 21 * 60
	var merchant := records[2]
	merchant.work_start_minute = 8 * 60
	merchant.work_end_minute = 18 * 60
	merchant.needs.hunger = 10.0
	merchant.needs.energy = 95.0

	var total_food_before := EconomyRules.total_system_resource(
		fixture.economy, ResourceType.FOOD
	)
	var total_wood_before := EconomyRules.total_system_resource(
		fixture.economy, ResourceType.WOOD
	)
	var total_stone_before := EconomyRules.total_system_resource(
		fixture.economy, ResourceType.STONE
	)
	var total_coin_before := EconomyRules.total_system_resource(
		fixture.economy, ResourceType.COIN
	)
	var village_food_before := fixture.economy.get_village_resource(ResourceType.FOOD)

	fixture.loop.run_ticks(160)

	harness.check(
		fixture.economy.get_village_resource(ResourceType.FOOD) > village_food_before,
		"merchant working at the market replenishes scarce village Food via trade"
	)
	harness.check_equals(
		EconomyRules.total_system_resource(fixture.economy, ResourceType.FOOD),
		total_food_before,
		"merchant never creates Food out of nothing"
	)
	harness.check_equals(
		EconomyRules.total_system_resource(fixture.economy, ResourceType.WOOD),
		total_wood_before,
		"merchant never creates Wood out of nothing"
	)
	harness.check_equals(
		EconomyRules.total_system_resource(fixture.economy, ResourceType.STONE),
		total_stone_before,
		"merchant never creates Stone out of nothing"
	)
	harness.check_equals(
		EconomyRules.total_system_resource(fixture.economy, ResourceType.COIN),
		total_coin_before,
		"merchant never creates Coin out of nothing"
	)


static func _test_food_consumption_linked_to_inhabitants(harness: TestHarness) -> void:
	var empty_fixture := _build_fixture(8 * 60, 0, 30, 10, 10, 50)
	empty_fixture.loop.run_ticks(1440)
	harness.check_equals(
		empty_fixture.economy.get_consumption(ResourceType.FOOD),
		0,
		"zero inhabitants consume zero Food over a full day"
	)

	var small_fixture := _build_fixture(8 * 60, 3, 40, 10, 10, 50, 90.0)
	small_fixture.loop.run_ticks(200)
	var small_consumed := small_fixture.economy.get_consumption(ResourceType.FOOD)

	var large_fixture := _build_fixture(8 * 60, 8, 40, 10, 10, 50, 90.0)
	large_fixture.loop.run_ticks(200)
	var large_consumed := large_fixture.economy.get_consumption(ResourceType.FOOD)

	harness.check(
		small_consumed >= 3,
		"three hungry inhabitants consume at least 3 rations (got %d)" % small_consumed
	)
	harness.check(
		large_consumed > small_consumed,
		"eight hungry inhabitants consume more Food than three (%d > %d)"
		% [large_consumed, small_consumed]
	)


static func _test_food_scarcity_affects_needs_without_mortality(
	harness: TestHarness
) -> void:
	var fed_fixture := _build_fixture(10 * 60, 2, 20, 10, 10, 40, 90.0)
	var scarce_fixture := _build_fixture(10 * 60, 2, 0, 10, 10, 40, 90.0)
	scarce_fixture.economy.market_inventory.set_amount(ResourceType.FOOD, 0)
	scarce_fixture.economy.set_workplace_ready("work_field", false)
	scarce_fixture.economy.set_workplace_ready("work_inn", false)
	fed_fixture.economy.set_workplace_ready("work_field", false)
	fed_fixture.economy.set_workplace_ready("work_inn", false)

	fed_fixture.loop.run_ticks(120)
	scarce_fixture.loop.run_ticks(120)

	var fed_npc := fed_fixture.npc_system.get_records()[0]
	var scarce_npc := scarce_fixture.npc_system.get_records()[0]

	harness.check_equals(
		scarce_fixture.economy.get_village_resource(ResourceType.FOOD),
		0,
		"scarce village Food stays at 0 and never goes negative"
	)
	harness.check(
		scarce_fixture.economy.has_shortage(ResourceType.FOOD),
		"economy reports an active Food shortage"
	)
	harness.check(
		scarce_fixture.economy.unfed_meal_attempts_period > 0,
		"unfed meal attempts are recorded during scarcity"
	)
	harness.check(
		scarce_npc.needs.hunger > fed_npc.needs.hunger + 30.0,
		"unfed inhabitant stays much hungrier than fed inhabitant (%.1f vs %.1f)"
		% [scarce_npc.needs.hunger, fed_npc.needs.hunger]
	)
	harness.check(
		scarce_npc.needs.wellbeing < fed_npc.needs.wellbeing - 5.0,
		"food scarcity reduces inhabitant wellbeing (%.1f vs %.1f)"
		% [scarce_npc.needs.wellbeing, fed_npc.needs.wellbeing]
	)
	harness.check_equals(
		scarce_fixture.npc_system.get_record_count(),
		2,
		"no inhabitant dies during food scarcity"
	)
	harness.check(scarce_npc.needs.are_valid(), "needs stay within valid 0..100 bounds")


static func _test_multi_day_determinism_and_non_negativity(harness: TestHarness) -> void:
	var first := _build_fixture(7 * 60, 10, 24, 12, 10, 60)
	var second := _build_fixture(7 * 60, 10, 24, 12, 10, 60)

	var any_negative := false
	for _day in 3:
		first.loop.run_ticks(SimulationClock.MINUTES_PER_DAY)
		second.loop.run_ticks(SimulationClock.MINUTES_PER_DAY)
		if not first.economy.village_inventory.are_all_non_negative():
			any_negative = true
		if not first.economy.market_inventory.are_all_non_negative():
			any_negative = true

	harness.check(
		not any_negative,
		"no resource becomes negative over 3 full simulated days (4320 ticks)"
	)
	harness.check_equals(
		first.economy.validate().size(),
		0,
		"economy validates cleanly after 3 simulated days"
	)
	harness.check(
		first.economy.get_production(ResourceType.FOOD) > 0
		and first.economy.get_consumption(ResourceType.FOOD) > 0,
		"both production and consumption occurred over 3 days"
	)
	harness.check_equals(
		var_to_str(first.economy.to_dict()),
		var_to_str(second.economy.to_dict()),
		"two 3-day runs from identical initial state produce identical economy snapshots"
	)
	harness.check_equals(
		var_to_str(first.npc_system.to_dict()),
		var_to_str(second.npc_system.to_dict()),
		"two 3-day runs from identical initial state produce identical NPC snapshots"
	)


# --- fixture -----------------------------------------------------------------


static func _build_fixture(
	start_tick: int,
	population_count: int,
	food: int,
	wood: int,
	stone: int,
	coin: int,
	override_hunger: float = -1.0
) -> EconomyFixture:
	var records := NpcRoster.build(population_count)
	if override_hunger >= 0.0:
		for record in records:
			record.needs.hunger = override_hunger
			record.needs.wellbeing = 75.0
	var places := _build_places()
	var roads: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-25, 0), Vector2(25, 0)])
	]
	var obstacles: Array[NpcRouteGraph.Obstacle] = []
	var graph := NpcRouteGraph.new(places, roads, obstacles)
	var npc_sys := NpcSimulationSystem.new(records, places, graph)
	var economy := EconomySystem.new(npc_sys, food, wood, stone, coin)
	npc_sys.initialize(start_tick)
	economy.initialize(start_tick)
	var loop := SimulationLoop.new()
	loop.tick_seconds = 0.05
	loop.max_steps_per_frame = 64
	loop.clock.tick = maxi(start_tick - 1, 0)
	loop.register_system(npc_sys)
	loop.register_system(economy)
	var fixture := EconomyFixture.new()
	fixture.loop = loop
	fixture.npc_system = npc_sys
	fixture.economy = economy
	return fixture


static func _build_places() -> NpcPlaceRegistry:
	var registry := NpcPlaceRegistry.new()
	for index in 10:
		registry.add(
			"home_%03d" % (index + 1),
			"Casa %d" % (index + 1),
			NpcPlace.Kind.HOME,
			Vector2(-18.0 + float(index) * 1.4, 2.0),
			0,
			0,
			true
		)
	registry.add("work_field", "Campi", NpcPlace.Kind.WORK, Vector2(-16, 0))
	registry.add("work_inn", "Locanda", NpcPlace.Kind.WORK, Vector2(-12, 0))
	registry.add("work_market", "Mercato", NpcPlace.Kind.WORK, Vector2(-8, 0))
	registry.add("work_hall", "Sala", NpcPlace.Kind.WORK, Vector2(-4, 0))
	registry.add("work_forge", "Fucina", NpcPlace.Kind.WORK, Vector2(0, 0))
	registry.add("work_garden", "Giardino", NpcPlace.Kind.WORK, Vector2(4, 0))
	registry.add("work_pond", "Stagno", NpcPlace.Kind.WORK, Vector2(8, 0))
	registry.add("work_workshop", "Bottega", NpcPlace.Kind.WORK, Vector2(12, 0))
	registry.add(
		"food_inn",
		"Locanda del Cervo Bianco",
		NpcPlace.Kind.FOOD,
		Vector2(2, 0),
		0,
		0,
		true
	)
	registry.add("social_plaza", "Piazza", NpcPlace.Kind.SOCIAL, Vector2(0, -2))
	registry.add("rest_inn", "Riposo", NpcPlace.Kind.REST, Vector2(4, 2), 0, 0)
	return registry
