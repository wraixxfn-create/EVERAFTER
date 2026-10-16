class_name TestDayCycleSystem
extends RefCounted
## Checks for `DayCycleSystem`: the pure functions that turn a time of day into
## a sun position, a day phase and a daylight factor.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("DayCycleSystem")

	harness.check_almost(
		DayCycleSystem.compute_sun_elevation(0.0),
		-DayCycleSystem.MAX_SUN_ELEVATION_DEG,
		0.0001,
		"the sun is lowest at midnight"
	)
	harness.check_almost(
		DayCycleSystem.compute_sun_elevation(0.5),
		DayCycleSystem.MAX_SUN_ELEVATION_DEG,
		0.0001,
		"the sun is highest at noon"
	)
	harness.check_almost(
		DayCycleSystem.compute_sun_elevation(0.25), 0.0, 0.0001, "the sun crosses the horizon at 06:00"
	)
	harness.check_almost(
		DayCycleSystem.compute_sun_elevation(0.75), 0.0, 0.0001, "the sun crosses the horizon at 18:00"
	)

	for step in 24:
		var progress := float(step) / 24.0
		var azimuth := DayCycleSystem.compute_sun_azimuth(progress)
		harness.check(azimuth >= 0.0 and azimuth < 360.0, "azimuth stays inside 0..360 (step %d)" % step)
	harness.check_not_equals(
		DayCycleSystem.compute_sun_azimuth(0.0),
		DayCycleSystem.compute_sun_azimuth(0.25),
		"the sun actually moves during the day"
	)

	harness.check_equals(
		DayCycleSystem.compute_phase(0), DayCycleSystem.Phase.NIGHT, "00:00 is night"
	)
	harness.check_equals(
		DayCycleSystem.compute_phase(6), DayCycleSystem.Phase.DAWN, "06:00 is dawn"
	)
	harness.check_equals(
		DayCycleSystem.compute_phase(12), DayCycleSystem.Phase.DAY, "12:00 is day"
	)
	harness.check_equals(
		DayCycleSystem.compute_phase(19), DayCycleSystem.Phase.DUSK, "19:00 is dusk"
	)
	harness.check_equals(
		DayCycleSystem.compute_phase(22), DayCycleSystem.Phase.NIGHT, "22:00 is night"
	)
	harness.check(
		DayCycleSystem.phase_name(DayCycleSystem.Phase.DAY) == "Giorno", "phase names are readable"
	)

	# --- integration with the clock through the system -----------------------
	var system := DayCycleSystem.new()
	harness.check_equals(system.get_system_name(), DayCycleSystem.SYSTEM_NAME, "system name is stable")
	harness.check_almost(
		system.get_daylight_factor(), 0.0, 0.0001, "no daylight before the first tick"
	)

	var clock := SimulationClock.new()
	clock.advance(720)  # noon
	system.on_tick(clock.tick, clock)
	harness.check_equals(system.phase, DayCycleSystem.Phase.DAY, "noon is the DAY phase")
	harness.check_almost(system.get_daylight_factor(), 1.0, 0.0001, "daylight is saturated at noon")
	harness.check(system.sun_elevation_deg > 0.0, "the sun is above the horizon at noon")

	clock.advance(720)  # next midnight
	system.on_tick(clock.tick, clock)
	harness.check_equals(system.phase, DayCycleSystem.Phase.NIGHT, "midnight is the NIGHT phase")
	harness.check_almost(system.get_daylight_factor(), 0.0, 0.0001, "no daylight at midnight")

	var snapshot := system.to_dict()
	var restored := DayCycleSystem.new()
	restored.from_dict(snapshot)
	harness.check_equals(restored.phase, system.phase, "to_dict/from_dict restores the phase")
	harness.check_almost(
		restored.sun_elevation_deg, system.sun_elevation_deg, 0.0001, "to_dict/from_dict restores the sun"
	)

	restored.reset()
	harness.check_equals(
		restored.phase, DayCycleSystem.Phase.NIGHT, "reset goes back to the initial state"
	)
