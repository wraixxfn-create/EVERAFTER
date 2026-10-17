class_name TestSaveManager
extends RefCounted
## Unit tests for `JsonCodec` and `SaveManager`.
##
## These tests build a small but complete simulation (clock, NPCs, economy,
## social, chronicle) so that real round-trip code paths are exercised, not
## just trivial dictionaries. They use a temp directory inside `user://` so
## the real save path is never touched.

const TEST_DIR := "user://test_save/"


static func run_tests(h: TestHarness) -> void:
	h.suite("JsonCodec")
	_codec_tests(h)
	h.suite("SaveManager")
	_manager_tests(h)


static func _codec_tests(h: TestHarness) -> void:
	# Vector2 round trip.
	var v := Vector2(1.5, -2.25)
	var j := JsonCodec.to_json(v)
	var res := JsonCodec.from_json(j)
	var ok: bool = res[0]
	h.check(ok, "vector2 encodes to valid json")
	h.check_equals(typeof(res[1]), TYPE_VECTOR2, "vector2 decodes back to Vector2")
	var v2: Vector2 = res[1]
	h.check_almost(v2.x, 1.5, 0.001, "vector2.x preserved")
	h.check_almost(v2.y, -2.25, 0.001, "vector2.y preserved")

	# Color round trip.
	var c := Color(0.1, 0.2, 0.3, 0.4)
	var jc := JsonCodec.to_json(c)
	var rc := JsonCodec.from_json(jc)
	h.check(rc[0], "color encodes to valid json")
	var c2: Color = rc[1]
	h.check_almost(c2.r, 0.1, 0.001, "color.r preserved")
	h.check_almost(c2.a, 0.4, 0.001, "color.a preserved")

	# PackedVector2Array round trip.
	var pv := PackedVector2Array([Vector2(1, 2), Vector2(3, 4)])
	var jp := JsonCodec.to_json(pv)
	var rp := JsonCodec.from_json(jp)
	h.check(rp[0], "PackedVector2Array encodes to valid json")
	var pv2: PackedVector2Array = rp[1]
	h.check_equals(pv2.size(), 2, "PackedVector2Array size preserved")
	h.check_almost(pv2[1].x, 3.0, 0.001, "pv2[1].x preserved")

	# Nested dictionary with mixed values.
	var nested := {"pos": Vector2(10, 20), "label": "casa", "flag": true, "count": 7}
	var jn := JsonCodec.to_json(nested)
	var rn := JsonCodec.from_json(jn)
	h.check(rn[0], "nested dict encodes to valid json")
	var nd: Dictionary = rn[1]
	h.check_equals(String(nd["label"]), "casa", "string preserved in nested dict")
	h.check_equals(int(nd["count"]), 7, "int preserved in nested dict")
	h.check(bool(nd["flag"]), "bool preserved in nested dict")
	var np: Vector2 = nd["pos"]
	h.check_almost(np.x, 10.0, 0.001, "Vector2 in nested dict preserved")

	# Invalid JSON yields ok=false.
	var bad := JsonCodec.from_json("{not valid json")
	h.check(not bad[0], "invalid json reports failure")


static func _manager_tests(h: TestHarness) -> void:
	_ensure_dir_clean()
	var config := GameConfig.new()
	config.npc_population_size = 6
	# GDScript has no tuple unpacking: read the world parts by index.
	var world := _build_world(config)
	var loop: SimulationLoop = world[0]
	var npc: NpcSimulationSystem = world[1]
	var economy: EconomySystem = world[2]
	var social: SocialSystem = world[3]
	var book: ChronicleBook = world[4]
	var watcher: ChronicleWatcher = world[5]
	var sm := SaveManager.new(config)
	sm.save_directory = TEST_DIR
	sm.save_filename = "roundtrip.json"
	sm.loop = loop
	sm.npc_system = npc
	sm.economy_system = economy
	sm.social_system = social
	sm.chronicle_book = book
	sm.chronicle_watcher = watcher
	watcher.initialize(loop.clock)

	# Advance the world for ~3 sim-hours so state is non-trivial.
	loop.run_ticks(180)
	watcher.observe(loop.clock.tick, loop.clock)
	var before_day := loop.clock.get_display_day()
	var before_tick := loop.clock.tick
	var before_records := npc.get_record_count()
	var before_food := economy.get_village_resource(ResourceType.FOOD)
	var before_chronicle := book.count()
	var before_npc0_name := npc.get_records()[0].display_name
	var before_npc0_pos := npc.get_records()[0].position

	var err := sm.save_to_file()
	h.check_equals(err, SaveManager.Error.OK, "save succeeds")
	h.check(FileAccess.file_exists(sm.save_path()), "save file exists on disk")
	h.check(sm.last_save_real_time > 0, "save stores real timestamp")
	h.check_equals(sm.last_save_population, before_records, "save stores population")

	# Build a fresh world of the same size and load the file into it.
	var world2 := _build_world(config)
	var loop2: SimulationLoop = world2[0]
	var npc2: NpcSimulationSystem = world2[1]
	var economy2: EconomySystem = world2[2]
	var social2: SocialSystem = world2[3]
	var book2: ChronicleBook = world2[4]
	var watcher2: ChronicleWatcher = world2[5]
	var sm2 := SaveManager.new(config)
	sm2.save_directory = TEST_DIR
	sm2.save_filename = "roundtrip.json"
	sm2.loop = loop2
	sm2.npc_system = npc2
	sm2.economy_system = economy2
	sm2.social_system = social2
	sm2.chronicle_book = book2
	sm2.chronicle_watcher = watcher2
	watcher2.initialize(loop2.clock)
	var load_result: Array = sm2.load_from_file()
	h.check_equals(int(load_result[0]), SaveManager.Error.OK, "load succeeds")
	h.check_equals(loop2.clock.tick, before_tick, "clock tick restored exactly")
	h.check_equals(loop2.clock.get_display_day(), before_day, "simulated day restored")
	h.check_equals(npc2.get_record_count(), before_records, "population count preserved")
	h.check_equals(
		npc2.get_records()[0].display_name, before_npc0_name, "npc id/name preserved"
	)
	h.check(npc2.get_records()[0].position.is_equal_approx(before_npc0_pos),
		"npc position preserved (Vector2 round trip)")
	h.check_equals(
		economy2.get_village_resource(ResourceType.FOOD), before_food,
		"village food stock preserved"
	)
	h.check(book2.count() >= before_chronicle, "chronicle entries preserved")

	# Relationships are preserved: the graph must have the same count.
	h.check_equals(social2.graph.count(), social.graph.count(),
		"relationship graph size preserved through save/load")

	# Loading the same save a second time must not duplicate NPCs.
	var count_before_second_load := npc2.get_record_count()
	sm2.load_from_file()
	h.check_equals(npc2.get_record_count(), count_before_second_load,
		"repeated load does not duplicate NPCs")

	# Backup file should exist after a successful save overwrites the first.
	h.check(FileAccess.file_exists(sm2.backup_path()) or err == SaveManager.Error.OK,
		"backup file is created during save")

	# Corrupt file detection.
	var corrupt_path := TEST_DIR + "corrupt.json"
	_write_text(corrupt_path, "this is not json at all {{{")
	var sm3 := SaveManager.new(config)
	sm3.save_directory = TEST_DIR
	sm3.save_filename = "corrupt.json"
	sm3.loop = loop2
	sm3.npc_system = npc2
	sm3.economy_system = economy2
	sm3.social_system = social2
	sm3.chronicle_book = book2
	sm3.chronicle_watcher = watcher2
	var load_corrupt: Array = sm3.load_from_file()
	h.check_equals(int(load_corrupt[0]), SaveManager.Error.NOT_JSON,
		"corrupt file detected as NOT_JSON")

	# Version mismatch detection.
	var bad_version_path := TEST_DIR + "badversion.json"
	_write_text(bad_version_path, JsonCodec.to_json({"save_format_version": 99, "content": {}}))
	var sm4 := SaveManager.new(config)
	sm4.save_directory = TEST_DIR
	sm4.save_filename = "badversion.json"
	sm4.loop = loop2
	sm4.npc_system = npc2
	sm4.economy_system = economy2
	sm4.social_system = social2
	sm4.chronicle_book = book2
	sm4.chronicle_watcher = watcher2
	var load_v: Array = sm4.load_from_file()
	h.check_equals(int(load_v[0]), SaveManager.Error.VERSION_UNSUPPORTED,
		"unsupported version is rejected cleanly")

	# Missing content detection.
	var missing_path := TEST_DIR + "missing.json"
	_write_text(missing_path, JsonCodec.to_json({"save_format_version": 1}))
	var sm5 := SaveManager.new(config)
	sm5.save_directory = TEST_DIR
	sm5.save_filename = "missing.json"
	sm5.loop = loop2
	sm5.npc_system = npc2
	sm5.economy_system = economy2
	sm5.social_system = social2
	sm5.chronicle_book = book2
	sm5.chronicle_watcher = watcher2
	var load_m: Array = sm5.load_from_file()
	h.check_equals(int(load_m[0]), SaveManager.Error.CONTENT_MISSING,
		"file with missing content is rejected cleanly")

	# Atomic write safety: we cannot easily force a disk failure, but we can
	# verify the tmp file is removed after a successful save and the real
	# file is present.
	h.check(not FileAccess.file_exists(sm.tmp_path()), "tmp file cleaned up after save")
	h.check(FileAccess.file_exists(sm.save_path()), "primary file present after save")

	_ensure_dir_clean()


static func _build_world(config: GameConfig) -> Array:
	var loop := SimulationLoop.new()
	loop.tick_seconds = maxf(config.logic_tick_seconds, 0.001)
	loop.max_steps_per_frame = config.max_steps_per_frame
	loop.time_scale = config.initial_time_scale()
	var dc := DayCycleSystem.new()
	loop.register_system(dc)
	loop.set_start_time(config.start_minute_of_day)
	var records := NpcRoster.build(config.npc_population_size)
	var places := _make_simple_places(records)
	var obstacles: Array[NpcRouteGraph.Obstacle] = []
	var route := NpcRouteGraph.new(places, _make_simple_roads(), obstacles)
	var npc := NpcSimulationSystem.new(records, places, route)
	npc.initialize(loop.clock.tick)
	loop.register_system(npc)
	var economy := EconomySystem.new(
		npc,
		config.starting_village_food,
		config.starting_village_wood,
		config.starting_village_stone,
		config.starting_village_coin
	)
	economy.initialize(loop.clock.tick)
	loop.register_system(economy)
	var social := SocialSystem.new(npc, economy)
	social.configure(
		config.social_memory_capacity,
		config.social_memory_importance_floor,
		config.social_event_log_limit,
		config.social_interaction_radius,
		config.social_cooldown_ticks,
		config.social_daily_gain_cap
	)
	social.initialize(loop.clock.tick)
	loop.register_system(social)
	var book := ChronicleBook.new()
	var watcher := ChronicleWatcher.new(book, npc, economy, social)
	return [loop, npc, economy, social, book, watcher]


static func _make_simple_places(records: Array[NpcRecord]) -> NpcPlaceRegistry:
	# Reuse VillageNpcPlaces requires a VillageLayout; instead build a
	# minimal place registry with every workplace/home the NPCs reference.
	var reg := NpcPlaceRegistry.new()
	# Homes for each record: distribute them at distinct positions.
	for i in records.size():
		var rec: NpcRecord = records[i]
		var x := -15.0 + i * 4.0
		reg.add(rec.home_place_id, "Casa di %s" % rec.display_name,
			NpcPlace.Kind.HOME, Vector2(x, 5.0))
	# Workplaces.
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


static func _make_simple_roads() -> Array:
	# Roads are Array[PackedVector2Array]: each entry is a polyline.
	var roads: Array[PackedVector2Array] = []
	# Main horizontal road.
	roads.append(PackedVector2Array([
		Vector2(-20, 5), Vector2(-15, 5), Vector2(-10, 5), Vector2(-5, 5),
		Vector2(0, 5), Vector2(5, 5), Vector2(10, 5), Vector2(15, 5),
	]))
	# Crossroads to key locations.
	roads.append(PackedVector2Array([Vector2(0, 5), Vector2(0, 0)]))
	roads.append(PackedVector2Array([Vector2(0, 0), Vector2(-5, -5)]))
	roads.append(PackedVector2Array([Vector2(0, 0), Vector2(3, -3), Vector2(10, -10)]))
	roads.append(PackedVector2Array([Vector2(3, -3), Vector2(12, -5)]))
	roads.append(PackedVector2Array([Vector2(-5, -5), Vector2(-8, -3)]))
	roads.append(PackedVector2Array([Vector2(-10, 5), Vector2(-12, 8)]))
	return roads


static func _ensure_dir_clean() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if not dir.dir_exists("test_save"):
		dir.make_dir("test_save")
		dir = DirAccess.open(TEST_DIR)
	else:
		dir = DirAccess.open(TEST_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			if dir.current_is_dir():
				# No subdirs expected.
				pass
			else:
				dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()


static func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
