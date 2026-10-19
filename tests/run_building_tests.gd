extends SceneTree
## Focused structural checks, without the main scene or rendering backend.
## godot --headless --path . --script res://tests/run_building_tests.gd


func _initialize() -> void:
	var harness := TestHarness.new()
	TestMeshBaker.run_tests(harness)
	TestBuildingArchitecture.run_tests(harness)
	TestBuildingReconstruction.run_tests(harness)
	harness.print_summary()
	quit(0 if harness.succeeded() else 1)
