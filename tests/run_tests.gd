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
##   "skipped" instead of silently passing (see `TestHarness.skip`);
## * the checks that need a scene tree and a physics server live in
##   `tests/run_world_tests.gd`, which is a separate runner for exactly that
##   reason.

func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
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
	TestTerrainRelaxer.run_tests(harness)
	TestAreaRegistry.run_tests(harness)
	TestVillageLayout.run_tests(harness)
	TestGroundSurfaces.run_tests(harness)
	TestVillageMaterials.run_tests(harness)
	TestMeshBaker.run_tests(harness)
	TestVillageArt.run_tests(harness)
	TestVegetation.run_tests(harness)
	TestBuildingArchitecture.run_tests(harness)
	TestBuildingReconstruction.run_tests(harness)
	# SkyRig references Game. Loading this one suite after autoload startup
	# avoids compiling that singleton dependency before it is registered.
	load("res://tests/unit/test_sky_rig.gd").run_tests(harness)
	TestNpcData.run_tests(harness)
	TestNpcRoster.run_tests(harness)
	TestNpcVisuals.run_tests(harness)
	TestNpcRouteGraph.run_tests(harness)
	TestNpcSimulation.run_tests(harness)
	TestVillageNpcPlaces.run_tests(harness)
	TestEconomyInventory.run_tests(harness)
	TestEconomySimulation.run_tests(harness)
	TestSocialRelationships.run_tests(harness)
	TestSocialSimulation.run_tests(harness)
	TestChronicleBook.run_tests(harness)
	TestSaveManager.run_tests(harness)
	TestOfflineCatchup.run_tests(harness)
	harness.print_summary()

	quit(1 if harness.failed_count() > 0 else 0)
