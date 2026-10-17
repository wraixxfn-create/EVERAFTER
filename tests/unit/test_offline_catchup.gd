class_name TestOfflineCatchup
extends RefCounted
## Unit tests for `OfflineCatchup`.

static func run_tests(h: TestHarness) -> void:
	h.suite("OfflineCatchup")
	var config := GameConfig.new()
	config.npc_population_size = 4
	var (loop, npc, economy, social, book, watcher) := _build_world(config)
	# Set a deterministic tick_seconds for math verification: 0.05s per tick
	# (same as default: 1 real second = 20 sim minutes).
	loop.tick_seconds = 0.05
	var catchup := OfflineCatchup.new(loop, watcher, book, config)
	catchup.max_offline_simulated_days = 5
	catchup.batch_ticks = 60

	# With no prior save (timestamp 0) nothing is applied.
	var res := catchup.run(0)
	h.check_equals(int(res["ticks_applied"]), 0, "no catchup with timestamp 0")

	# With elapsed below the safety floor (30s) nothing is applied.
	var now := int(Time.get_unix_time_from_system())
	res = catchup.run(now - 10)
	h.check_equals(int(res["ticks_applied"]), 0, "no catchup below 30 real seconds")

	# Advance 3 real minutes = 180 real seconds. At 0.05s/tick and scale 1.0,
	# 180 / 0.05 = 3600 ticks = 2.5 sim-days.
	var start_tick := loop.clock.tick
	res = catchup.run(now - 180)
	h.check(int(res["ticks_applied"]) > 0, "catchup applies ticks after 3 real minutes")
	var expected := int(180.0 / 0.05 * 1.0)
	h.check_equals(int(res["ticks_applied"]), expected,
		"ticks_applied matches formula (3 real min → 3600 sim minutes)")
	h.check_equals(loop.clock.tick - start_tick, expected, "loop advanced by the expected ticks")
	h.check(not bool(res["was_capped"]), "short catchup is not capped")

	# Calling run again with the same (old) timestamp must not duplicate
	# effects. We pass the same timestamp again; because the clock has moved
	# forward, elapsed is now negative and nothing should advance.
	var tick_before := loop.clock.tick
	res = catchup.run(now - 180)
	h.check_equals(loop.clock.tick, tick_before,
		"second run with same timestamp does not duplicate ticks")

	# Capping: simulate a save written 10 real days ago.
	# 10 days * 86400 sec = 864000 real sec / 0.05 = 17 280 000 ticks ≈ 12000
	# sim-days. Cap is 5 days = 7200 ticks.
	var long_ago := now - 10 * 86400
	var start_tick2 := loop.clock.tick
	res = catchup.run(long_ago)
	h.check(bool(res["was_capped"]), "long-ago catchup is capped")
	h.check_equals(int(res["ticks_applied"]), 5 * 1440, "capped to max_offline_simulated_days (5)")
	h.check_equals(loop.clock.tick - start_tick2, 5 * 1440,
		"loop advances exactly by the capped amount")

	# Clock skew in the future (save written later than now + tolerance)
	# must be ignored, not advance anything.
	var future := now + 3600  # 1 hour in the future
	var tick_before3 := loop.clock.tick
	res = catchup.run(future)
	h.check_equals(int(res["ticks_applied"]), 0, "future timestamps do not advance the clock")
	h.check_equals(loop.clock.tick, tick_before3, "clock unchanged on clock skew")

	# Chronicle receives a system entry about the capped catch-up.
	var found_system_entry := false
	for e in book.get_entries():
		if e.category == ChronicleEntry.Category.SYSTEM \
				and "avanzamento limitato" in e.summary:
			found_system_entry = true
			break
	h.check(found_system_entry, "capped catchup writes a chronicle entry")

	# After catch-up the economy still has non-negative resources (no
	# infinite resources, no destruction).
	for rid in [ResourceType.FOOD, ResourceType.WOOD, ResourceType.STONE, ResourceType.COIN]:
		var v := economy.get_village_resource(rid)
		h.check(v >= 0, "village %s stays non-negative after catch-up (%d)" % [rid, v])


static func _build_world(config: GameConfig) -> Array:
	# Duplicated from test_save_manager helper but kept local so tests are
	# independent.
	var loop := SimulationLoop.new()
	loop.tick_seconds = maxf(config.logic_tick_seconds, 0.001)
	loop.max_steps_per_frame = config.max_steps_per_frame
	loop.time_scale = config.initial_time_scale()
	var dc := DayCycleSystem.new()
	loop.register_system(dc)
	loop.set_start_time(config.start_minute_of_day)
	var records := NpcRoster.build(config.npc_population_size)
	var places := _places(records)
	var route := NpcRouteGraph.new(places, _roads(), [])
	var npc := NpcSimulationSystem.new(records, places, route)
	npc.initialize(loop.clock.tick)
	loop.register_system(npc)
	var economy := EconomySystem.new(npc,
		config.starting_village_food, config.starting_village_wood,
		config.starting_village_stone, config.starting_village_coin)
	economy.initialize(loop.clock.tick)
	loop.register_system(economy)
	var social := SocialSystem.new(npc, economy)
	social.configure(config.social_memory_capacity,
		config.social_memory_importance_floor, config.social_event_log_limit,
		config.social_interaction_radius, config.social_cooldown_ticks,
		config.social_daily_gain_cap)
	social.initialize(loop.clock.tick)
	loop.register_system(social)
	var book := ChronicleBook.new()
	var watcher := ChronicleWatcher.new(book, npc, economy, social)
	return [loop, npc, economy, social, book, watcher]


static func _places(records: Array[NpcRecord]) -> NpcPlaceRegistry:
	var reg := NpcPlaceRegistry.new()
	for i in records.size():
		var rec: NpcRecord = records[i]
		reg.add(rec.home_place_id, "Casa", NpcPlace.Kind.HOME, Vector2(-15.0 + i * 4.0, 5.0))
	reg.add("work_field", "Campi", NpcPlace.Kind.WORK, Vector2(10, -10))
	reg.add("work_inn", "Locanda", NpcPlace.Kind.WORK, Vector2(0, 0))
	reg.add("work_market", "Mercato", NpcPlace.Kind.WORK, Vector2(-5, -5))
	reg.add("work_hall", "Sala", NpcPlace.Kind.WORK, Vector2(3, -3))
	reg.add("work_forge", "Fucina", NpcPlace.Kind.WORK, Vector2(12, -5))
	reg.add("work_garden", "Giardino", NpcPlace.Kind.WORK, Vector2(-8, -3))
	reg.add("work_pond", "Stagno", NpcPlace.Kind.WORK, Vector2(-12, 8))
	reg.add("work_workshop", "Bottega", NpcPlace.Kind.WORK, Vector2(15, 5))
	reg.add("food_inn", "Locanda", NpcPlace.Kind.FOOD, Vector2(0, 0), 660, 1380, true, 12)
	reg.add("food_market", "Mercato", NpcPlace.Kind.FOOD, Vector2(-5, -5), 480, 1080, true, 10)
	reg.add("social_plaza", "Piazza", NpcPlace.Kind.SOCIAL, Vector2(0, -3))
	return reg


static func _roads() -> Array:
	var roads: Array[PackedVector2Array] = []
	roads.append(PackedVector2Array([Vector2(-20, 5), Vector2(0, 5), Vector2(20, 5)]))
	roads.append(PackedVector2Array([Vector2(0, 5), Vector2(0, 0)]))
	roads.append(PackedVector2Array([Vector2(0, 0), Vector2(-5, -5)]))
	roads.append(PackedVector2Array([Vector2(0, 0), Vector2(10, -10)]))
	roads.append(PackedVector2Array([Vector2(0, 0), Vector2(12, -5)]))
	roads.append(PackedVector2Array([Vector2(-5, -5), Vector2(-8, -3)]))
	roads.append(PackedVector2Array([Vector2(-20, 5), Vector2(-12, 8)]))
	return roads
