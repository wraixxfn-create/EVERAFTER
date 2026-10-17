extends SceneTree
## Integration runner: boots the real main scene headless and checks it.
##
##     godot --headless --path . --script res://tests/run_world_tests.gd
##
## Unlike `tests/run_tests.gd`, this one needs a scene tree and a physics server:
## it instantiates `main_world.tscn`, lets it settle for a few dozen physics
## frames and then interrogates the live world. It still needs no GPU, so it
## runs in CI and on a laptop with the screen off.
##
## Exit code is 0 when every check passed, 1 otherwise.

const MAIN_SCENE := "res://src/world/scenes/main_world.tscn"
const WORLD_TESTS := "res://tests/integration/test_world_scene.gd"
const SETTLE_FRAMES := 45
const WATCH_FRAMES := 120

var _harness := TestHarness.new()
var _world: Node3D = null
var _tests: GDScript = null


func _initialize() -> void:
	print("==========================================================")
	print("EVERAFTER world integration suite")
	print("Godot %s" % Engine.get_version_info().string)
	print("==========================================================")
	_run()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	_harness.check(packed != null, "the main scene loads: %s" % MAIN_SCENE)
	if packed == null:
		_finish()
		return
	_world = packed.instantiate() as Node3D
	_harness.check(_world != null, "the main scene instantiates")
	if _world == null:
		_finish()
		return
	root.add_child(_world)

	await process_frame
	for _frame in SETTLE_FRAMES:
		await physics_frame

	# Loaded at runtime, not referenced statically: this entry script is compiled
	# before the autoloads are registered, and the integration module (and the
	# scripts it types) use `Game` and `EventBus` by name. A static reference
	# would make the whole runner fail to compile.
	_tests = load(WORLD_TESTS)
	_harness.check(_tests != null, "the integration module compiles: %s" % WORLD_TESTS)
	if _tests == null:
		_finish()
		return
	_tests.call("check_structure", _harness, _world)
	_tests.call("check_player_settles", _harness, _world)

	# Let the world run and watch the player's clearance from the ground: this is
	# the check that catches "the player slowly sinks through the terrain".
	var terrain: TerrainGenerator = _world.get_terrain()
	var player: CharacterBody3D = _world.get_player()
	var min_clearance := INF
	if terrain != null and player != null:
		for _frame in WATCH_FRAMES:
			await physics_frame
			var ground := terrain.height_at(player.global_position.x, player.global_position.z)
			min_clearance = minf(min_clearance, player.global_position.y - ground)
	_tests.call("check_player_stays_up", _harness, min_clearance)

	_tests.call("check_player_collides", _harness, _world)
	_tests.call("check_areas", _harness, _world)
	_tests.call("check_budget", _harness, _world)
	await _tests.call("check_npcs", _harness, _world, self)
	_tests.call(
		"check_terrain_collision", _harness, _world, root.world_3d.direct_space_state
	)
	_finish()


func _finish() -> void:
	# Note: quitting from a script leaves the dummy renderer holding a handful of
	# RIDs, so the engine prints "leaked at exit" lines after this summary. That
	# is an artefact of the scripted shutdown, not a leak in the game: freeing
	# the world first produces exactly the same output.
	_harness.print_summary()
	quit(0 if _harness.succeeded() else 1)
