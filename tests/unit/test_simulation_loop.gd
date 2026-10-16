class_name TestSimulationLoop
extends RefCounted
## Checks for `SimulationLoop`: the fixed-timestep accumulator, the pause flag,
## the spiral-of-death guard, system ordering and the determinism guarantee.


## Records every tick it sees, so the tests can assert order and count.
class RecordingSystem extends SimulationSystem:
	var system_name: String = "recording"
	var ticks_seen: PackedInt32Array = []
	var reset_count: int = 0

	func get_system_name() -> String:
		return system_name

	func on_tick(tick: int, _clock: SimulationClock) -> void:
		ticks_seen.append(tick)

	func reset() -> void:
		reset_count += 1
		ticks_seen = PackedInt32Array()

	func to_dict() -> Dictionary:
		return {"ticks_seen": ticks_seen.size()}

	func from_dict(data: Dictionary) -> void:
		ticks_seen = PackedInt32Array()
		ticks_seen.resize(int(data.get("ticks_seen", 0)))


class DayRecorder extends RefCounted:
	var days: PackedInt32Array = []

	func on_day_advanced(display_day: int) -> void:
		days.append(display_day)


static func run_tests(harness: TestHarness) -> void:
	harness.suite("SimulationLoop")

	# --- accumulator ---------------------------------------------------------
	var loop := SimulationLoop.new()
	loop.tick_seconds = 0.05
	harness.check_equals(loop.update(0.1), 2, "0.1s of real time is 2 ticks at x1")
	harness.check_equals(loop.clock.tick, 2, "the clock advanced by 2 ticks")

	loop = SimulationLoop.new()
	loop.tick_seconds = 0.05
	var total_steps := 0
	for _i in 4:
		total_steps += loop.update(0.03)
	harness.check_equals(total_steps, 2, "leftover time is carried over, never lost")
	harness.check_equals(loop.clock.tick, 2, "0.12s of real time is 2 whole ticks")

	# --- pause and speed -----------------------------------------------------
	loop = SimulationLoop.new()
	loop.set_paused(true)
	harness.check_equals(loop.update(1.0), 0, "a paused loop produces no ticks")
	loop.set_paused(false)
	harness.check(loop.update(1.0) > 0, "resuming produces ticks again")

	loop = SimulationLoop.new()
	loop.set_time_scale(0.0)
	harness.check_equals(loop.update(1.0), 0, "speed x0 behaves like a pause")

	# Speed multiplies the tick rate. Two details make this test exact instead
	# of approximate, both found by actually running the suite:
	# * `tick_seconds` is a power of two, so the accumulator stays exact in
	#   binary floating point. With the default 0.05 the 20th tick is skipped
	#   because 1.0 - 19 * 0.05 is a hair below 0.05.
	# * `max_steps_per_frame` is raised, otherwise the spiral-of-death guard
	#   (default 12) caps the burst and the multiplier is never observable.
	var slow_loop := SimulationLoop.new()
	slow_loop.tick_seconds = 0.25
	slow_loop.max_steps_per_frame = 64
	var ticks_x1 := slow_loop.update(1.0)
	loop = SimulationLoop.new()
	loop.tick_seconds = 0.25
	loop.max_steps_per_frame = 64
	loop.set_time_scale(4.0)
	var ticks_x4 := loop.update(1.0)
	harness.check_equals(ticks_x1, 4, "1 real second at x1 is 4 ticks of 0.25s")
	harness.check_equals(ticks_x4, 16, "speed x4 produces four times the ticks")
	harness.check_equals(ticks_x4, ticks_x1 * 4, "the speed multiplier is linear")

	# The guard deliberately wins over the multiplier: a single frame is never
	# allowed to simulate more than `max_steps_per_frame` ticks.
	loop = SimulationLoop.new()
	loop.set_time_scale(4.0)
	harness.check_equals(
		loop.update(0.25),
		loop.max_steps_per_frame,
		"a fast frame is still capped by max_steps_per_frame"
	)

	# --- spiral of death guard ----------------------------------------------
	loop = SimulationLoop.new()
	loop.tick_seconds = 0.05
	loop.max_steps_per_frame = 3
	harness.check_equals(loop.update(10.0), 3, "a huge frame is capped by max_steps_per_frame")
	harness.check_equals(loop.clock.tick, 3, "the backlog is dropped, not simulated at once")
	harness.check_equals(loop.update(0.05), 1, "the loop keeps working after a capped frame")

	# --- systems -------------------------------------------------------------
	loop = SimulationLoop.new()
	var first_system := RecordingSystem.new()
	first_system.system_name = "first"
	var second_system := RecordingSystem.new()
	second_system.system_name = "second"
	loop.register_system(first_system)
	loop.register_system(second_system)
	harness.check_equals(loop.get_system_count(), 2, "both systems are registered")
	harness.check_equals(loop.get_system_names(), PackedStringArray(["first", "second"]), "order kept")
	harness.check(loop.get_system("second") == second_system, "get_system finds by name")
	harness.check(loop.get_system("missing") == null, "unknown system name returns null")

	loop.run_ticks(3)
	harness.check_equals(
		first_system.ticks_seen, PackedInt32Array([1, 2, 3]), "first system saw 3 ticks"
	)
	harness.check_equals(
		second_system.ticks_seen, PackedInt32Array([1, 2, 3]), "second system saw 3 ticks"
	)
	harness.check_equals(loop.clock.tick, 3, "run_ticks advances the clock without real time")

	second_system.enabled = false
	loop.run_ticks(2)
	harness.check_equals(first_system.ticks_seen.size(), 5, "enabled system keeps ticking")
	harness.check_equals(second_system.ticks_seen.size(), 3, "disabled system is skipped")

	# --- start time ----------------------------------------------------------
	loop = SimulationLoop.new()
	var start_system := RecordingSystem.new()
	loop.register_system(start_system)
	loop.set_start_time(420)
	harness.check_equals(loop.clock.get_time_text(), "07:00", "the world can start at 07:00")
	harness.check_equals(loop.clock.get_display_day(), 1, "the starting time stays on day 1")
	harness.check_equals(
		start_system.ticks_seen.size(), 1, "systems are initialised at the start time"
	)
	loop.set_start_time(99999)
	harness.check_equals(loop.clock.get_time_text(), "23:59", "the start time is clamped to day 1")
	loop.set_start_time(-5)
	harness.check_equals(loop.clock.get_time_text(), "00:00", "the start time cannot go below 0")

	# --- day rollover signal -------------------------------------------------
	loop = SimulationLoop.new()
	var day_recorder := DayRecorder.new()
	loop.day_advanced.connect(day_recorder.on_day_advanced)
	loop.run_ticks(SimulationClock.MINUTES_PER_DAY + 5)
	harness.check_equals(
		day_recorder.days, PackedInt32Array([2]), "day_advanced fires once at midnight"
	)
	harness.check_equals(loop.clock.get_display_day(), 2, "the clock is on day 2")

	# --- reset and serialisation ---------------------------------------------
	loop = SimulationLoop.new()
	var tracked := RecordingSystem.new()
	loop.register_system(tracked)
	loop.run_ticks(10)
	loop.reset()
	harness.check_equals(loop.clock.tick, 0, "reset rewinds the clock")
	harness.check_equals(tracked.reset_count, 1, "reset is forwarded to the systems")
	harness.check_equals(tracked.ticks_seen.size(), 0, "system state is cleared on reset")

	loop.run_ticks(500)
	var snapshot := loop.to_dict()
	var other := SimulationLoop.new()
	var other_system := RecordingSystem.new()
	other.register_system(other_system)
	other.from_dict(snapshot)
	harness.check_equals(other.clock.tick, 500, "from_dict restores the clock")
	harness.check_equals(other_system.ticks_seen.size(), 500, "system snapshots are restored by name")

	# --- determinism ---------------------------------------------------------
	var left := SimulationLoop.new()
	var right := SimulationLoop.new()
	var deltas := [0.016, 0.034, 0.008, 0.05, 0.017, 0.12, 0.033]
	for delta in deltas:
		left.update(delta)
		right.update(delta)
	harness.check_equals(left.clock.tick, right.clock.tick, "same deltas give the same tick count")
	harness.check_equals(
		left.clock.get_time_text(), right.clock.get_time_text(), "same deltas give the same world time"
	)

	var ticks_before := loop.clock.tick
	loop.run_ticks(-5)
	harness.check_equals(loop.clock.tick, ticks_before, "run_ticks ignores a negative count")
