extends SceneTree
## Headless test runner for EVERAFTER.
##
## Run it from the project root with a Godot 4 executable on PATH:
##
##     godot --headless --path . --script res://tests/run_tests.gd
##
## or through the wrapper, which also runs the static checks:
##
##     bash tools/run_checks.sh
##
## Exit code is 0 when every check passed and 1 when at least one failed, so it
## can be wired into CI without any extra glue.
##
## Notes:
## * the runner drives plain `RefCounted` classes only: no scene is instanced
##   and no autoload is required, which is what keeps it runnable with
##   `--headless` on a machine without a GPU;
## * checks that would need a real rendering backend report themselves as
##   "skipped" instead of silently passing (see `TestHarness.skip`).

func _initialize() -> void:
	print("==========================================================")
	print("EVERAFTER headless test suite")
	print("Godot %s" % Engine.get_version_info().string)
	print("==========================================================")

	var harness := TestHarness.new()
	TestGameConfig.run_tests(harness)
	TestSimulationClock.run_tests(harness)
	TestSimulationLoop.run_tests(harness)
	TestDayCycleSystem.run_tests(harness)
	TestTerrainGenerator.run_tests(harness)
	harness.print_summary()

	quit(1 if harness.failed_count() > 0 else 0)
