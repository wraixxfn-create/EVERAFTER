class_name TestAreaRegistry
extends RefCounted
## Checks for `AreaRegistry`: circular areas, corridors, priority and the
## fallback name shown when the player is out in the open.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("AreaRegistry")

	var registry := AreaRegistry.new()
	harness.check_equals(registry.get_area_count(), 0, "a fresh registry is empty")
	harness.check_equals(
		registry.area_at(Vector2.ZERO),
		AreaRegistry.FALLBACK_AREA_NAME,
		"an empty registry always answers open country"
	)
	harness.check(not registry.is_inside_named_area(Vector2.ZERO), "nothing is named yet")

	registry.add_circle("Piazza", Vector2.ZERO, 10.0, 5)
	registry.add_circle("Locanda", Vector2(8.0, 0.0), 4.0, 9)
	registry.add_area(
		"Via del Nord",
		PackedVector2Array([Vector2(0, -10), Vector2(0, -40)]),
		3.0,
		2
	)
	harness.check_equals(registry.get_area_count(), 3, "three areas are registered")
	harness.check(
		registry.get_area_names().has("Piazza"), "area names are readable"
	)

	# --- containment ---------------------------------------------------------
	harness.check_equals(registry.area_at(Vector2.ZERO), "Piazza", "the centre is the plaza")
	harness.check_equals(
		registry.area_at(Vector2(-9.5, 0.0)), "Piazza", "the plaza reaches its radius"
	)
	harness.check_equals(
		registry.area_at(Vector2(-11.0, 0.0)),
		AreaRegistry.FALLBACK_AREA_NAME,
		"past the radius is open country"
	)
	harness.check(registry.is_inside_named_area(Vector2.ZERO), "containment is queryable")

	# --- priority --------------------------------------------------------------
	# (8, 0) is inside both the plaza (r=10) and the inn (r=4); the inn has the
	# higher priority, so the specific place wins over the general one.
	harness.check_equals(
		registry.area_at(Vector2(8.0, 0.0)),
		"Locanda",
		"a higher priority area wins inside its own radius"
	)
	harness.check_equals(
		registry.area_at(Vector2(2.0, 0.0)),
		"Piazza",
		"outside the small area the larger one still applies"
	)

	# --- corridors -------------------------------------------------------------
	harness.check_equals(
		registry.area_at(Vector2(0.0, -25.0)), "Via del Nord", "a corridor covers its polyline"
	)
	harness.check_equals(
		registry.area_at(Vector2(5.0, -25.0)),
		AreaRegistry.FALLBACK_AREA_NAME,
		"a corridor does not cover ground away from its line"
	)
	harness.check_equals(
		registry.area_at(Vector2(0.0, -45.0)),
		AreaRegistry.FALLBACK_AREA_NAME,
		"a corridor stops at its last point"
	)

	# --- degenerate input --------------------------------------------------------
	var single := AreaRegistry.new()
	single.add_circle("Point", Vector2(3.0, 4.0), 2.0)
	harness.check_equals(single.area_at(Vector2(3.0, 4.0)), "Point", "a point area works")
	harness.check_equals(
		single.area_at(Vector2(3.0, 7.0)),
		AreaRegistry.FALLBACK_AREA_NAME,
		"a point area has a hard edge"
	)
	var empty := AreaRegistry.Area.new()
	harness.check(
		is_inf(empty.distance_to_polyline(Vector2.ONE)),
		"an area without points contains nothing"
	)
	harness.check_almost(
		AreaRegistry.distance_to_segment(Vector2(0, 1), Vector2(-5, 0), Vector2(5, 0)),
		1.0,
		0.0001,
		"segment distance is the perpendicular distance"
	)
	harness.check_almost(
		AreaRegistry.distance_to_segment(Vector2(9, 0), Vector2(-5, 0), Vector2(5, 0)),
		4.0,
		0.0001,
		"past the end of a segment the distance is to the endpoint"
	)
	harness.check_almost(
		AreaRegistry.distance_to_polyline(Vector2(0, 0), PackedVector2Array([Vector2(2, 0)])),
		2.0,
		0.0001,
		"a single point polyline measures to that point"
	)
