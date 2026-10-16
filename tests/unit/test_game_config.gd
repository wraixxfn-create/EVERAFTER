class_name TestGameConfig
extends RefCounted
## Checks for `GameConfig`: defaults are usable, broken data is reported and
## never crashes the boot, and the shipped resource file is consistent.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("GameConfig")

	var config := GameConfig.new()
	harness.check(config.validate().is_empty(), "the code defaults validate")
	harness.check(config.project_title == "EVERAFTER", "the project title is set")
	harness.check(config.logic_tick_seconds > 0.0, "the tick length is positive")
	harness.check_equals(config.validated_time_scale_presets().size(), 3, "three speed presets")
	harness.check_equals(config.initial_time_scale(), 1.0, "the world starts at speed x1")
	harness.check_equals(config.clamped_time_scale_index(99), 2, "preset index is clamped high")
	harness.check_equals(config.clamped_time_scale_index(-5), 0, "preset index is clamped low")
	harness.check(config.save_format_version >= 1, "the save format is versioned from day one")
	harness.check_equals(config.start_minute_of_day, 420, "the world starts at 07:00 of day 1")

	# --- broken data must be reported, not fatal -----------------------------
	var broken := GameConfig.new()
	broken.time_scale_presets = PackedFloat32Array()
	harness.check_equals(
		broken.validated_time_scale_presets().size(), 3, "empty presets fall back to the defaults"
	)
	harness.check(broken.validate().size() > 0, "empty presets are reported as a problem")
	harness.check(broken.initial_time_scale() > 0.0, "a broken config still yields a usable speed")

	var negative := GameConfig.new()
	negative.time_scale_presets = PackedFloat32Array([1.0, -2.0])
	harness.check(negative.validate().size() > 0, "negative presets are reported as a problem")

	var tiny := GameConfig.new()
	tiny.logic_tick_seconds = 0.0
	tiny.terrain_size_cells = 2
	harness.check(tiny.validate().size() >= 2, "tick length and terrain size are validated")

	# --- resource loading ----------------------------------------------------
	var missing := GameConfig.load_or_default("res://tests/data/__missing__.tres")
	harness.check(missing != null, "a missing resource falls back to the code defaults")
	harness.check(missing.validate().is_empty(), "the fallback config validates")

	var shipped := GameConfig.load_or_default()
	harness.check(shipped != null, "config/game_config.tres loads")
	if shipped != null:
		harness.check(shipped.validate().is_empty(), "the shipped config validates")
		harness.check(
			shipped.terrain_size_cells >= 16, "the shipped terrain size is inside the supported range"
		)
