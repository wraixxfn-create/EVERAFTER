class_name TestSimulationClock
extends RefCounted
## Checks for `SimulationClock`: the day/minute reading, the day rollover,
## determinism and the serialisation round trip.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("SimulationClock")

	var clock := SimulationClock.new()
	harness.check_equals(clock.tick, 0, "a fresh clock starts at tick 0")
	harness.check_equals(clock.get_display_day(), 1, "a fresh clock is on day 1")
	harness.check_equals(clock.get_day_index(), 0, "a fresh clock has day index 0")
	harness.check_equals(clock.get_time_text(), "00:00", "a fresh clock reads 00:00")
	harness.check_equals(clock.get_elapsed_sim_seconds(), 0, "a fresh clock has no elapsed time")

	clock.advance(60)
	harness.check_equals(clock.get_time_text(), "01:00", "60 ticks are one simulated hour")
	harness.check_equals(clock.get_display_day(), 1, "still day 1 after one hour")
	harness.check_equals(clock.get_hour(), 1, "hour is 1 after 60 ticks")
	harness.check_equals(clock.get_minute(), 0, "minute is 0 after 60 ticks")
	harness.check_equals(clock.get_elapsed_sim_seconds(), 3600, "60 ticks are 3600 simulated seconds")

	clock.advance(1380)
	harness.check_equals(clock.tick, 1440, "ticks accumulate")
	harness.check_equals(clock.get_display_day(), 2, "1440 ticks roll the world over to day 2")
	harness.check_equals(clock.get_day_index(), 1, "day index is 1 on day 2")
	harness.check_equals(clock.get_time_text(), "00:00", "a new day starts at midnight")
	harness.check_equals(clock.get_elapsed_sim_days(), 1, "one whole day elapsed")
	harness.check_almost(clock.get_day_progress(), 0.0, 0.0001, "day progress restarts at 0")

	clock.advance(720)
	harness.check_almost(clock.get_day_progress(), 0.5, 0.0001, "720 ticks are half a day")
	harness.check_equals(clock.get_hour(), 12, "720 ticks into the day is noon")

	clock.advance(-10)
	harness.check_equals(clock.tick, 2160, "negative steps are ignored")
	clock.tick = -5
	harness.check_equals(clock.tick, 0, "the tick counter cannot go negative")

	var first := SimulationClock.new()
	var second := SimulationClock.new()
	first.advance(4321)
	second.advance(4321)
	# The expected value is written out on purpose: it proves that the
	# `_to_string()` virtual really is dispatched. If the override ever stops
	# being applied, both sides collapse to `<RefCounted#...>` and this fails.
	harness.check_equals(str(first), "day 4 00:01 (tick 4321)", "_to_string formats the reading")
	harness.check_equals(str(first), str(second), "same ticks give the same reading")

	var restored := SimulationClock.new()
	restored.from_dict(first.to_dict())
	harness.check_equals(restored.tick, first.tick, "to_dict/from_dict round trip keeps the tick")
	harness.check_equals(
		restored.get_display_day(), first.get_display_day(), "restored clock reports the same day"
	)

	harness.check_equals(SimulationClock.format_minutes(0), "00:00", "midnight formats as 00:00")
	harness.check_equals(SimulationClock.format_minutes(754), "12:34", "754 minutes format as 12:34")
	harness.check_equals(SimulationClock.format_minutes(1439), "23:59", "last minute of the day")
	harness.check_equals(SimulationClock.format_minutes(-60), "23:00", "negative minutes wrap around")
