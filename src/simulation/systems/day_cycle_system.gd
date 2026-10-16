class_name DayCycleSystem
extends SimulationSystem
## Derives the sun position and the phase of the day from the simulated clock.
##
## This is the first real system of the simulation and it is intentionally
## tiny: its only job is to prove that the pipeline
## `SimulationClock -> SimulationSystem -> world/UI` works, end to end, without
## touching the scene tree from inside the simulation.
##
## `MainWorld` (in `world/`) reads [member sun_elevation_deg],
## [member sun_azimuth_deg] and [member phase] every frame and moves the light
## accordingly. Nothing here knows that a light exists.

enum Phase {
	NIGHT = 0,
	DAWN = 1,
	DAY = 2,
	DUSK = 3,
}

const SYSTEM_NAME := "day_cycle"

## Highest elevation reached at solar noon, in degrees.
const MAX_SUN_ELEVATION_DEG := 62.0
const DAWN_START_HOUR := 5
const DAY_START_HOUR := 8
const DUSK_START_HOUR := 18
const NIGHT_START_HOUR := 21

## Fraction of the day already elapsed (0.0 .. 0.9993).
var day_progress: float = 0.0
var sun_elevation_deg: float = -MAX_SUN_ELEVATION_DEG
var sun_azimuth_deg: float = 0.0
var phase: int = Phase.NIGHT


func get_system_name() -> String:
	return SYSTEM_NAME


func on_tick(_tick: int, clock: SimulationClock) -> void:
	day_progress = clock.get_day_progress()
	sun_elevation_deg = compute_sun_elevation(day_progress)
	sun_azimuth_deg = compute_sun_azimuth(day_progress)
	phase = compute_phase(clock.get_hour())


func reset() -> void:
	day_progress = 0.0
	sun_elevation_deg = compute_sun_elevation(0.0)
	sun_azimuth_deg = compute_sun_azimuth(0.0)
	phase = compute_phase(0)


## 0.0 at night, 1.0 when the sun is clearly above the horizon.
## Used by the world to fade light energy, sky colours and ambient light.
func get_daylight_factor() -> float:
	return clampf(sun_elevation_deg / 12.0, 0.0, 1.0)


func get_phase_name() -> String:
	return phase_name(phase)


func to_dict() -> Dictionary:
	return {
		"day_progress": day_progress,
		"sun_elevation_deg": sun_elevation_deg,
		"sun_azimuth_deg": sun_azimuth_deg,
		"phase": phase,
	}


func from_dict(data: Dictionary) -> void:
	day_progress = float(data.get("day_progress", 0.0))
	sun_elevation_deg = float(data.get("sun_elevation_deg", -MAX_SUN_ELEVATION_DEG))
	sun_azimuth_deg = float(data.get("sun_azimuth_deg", 0.0))
	phase = int(data.get("phase", Phase.NIGHT))


## Pure function of the time of day: -MAX at midnight, +MAX at noon, 0 at
## 06:00 and 18:00. Kept static so it can be unit tested without a world.
static func compute_sun_elevation(progress: float) -> float:
	return -cos(progress * TAU) * MAX_SUN_ELEVATION_DEG


## Pure function of the time of day: 0..360 degrees, one full turn per day.
static func compute_sun_azimuth(progress: float) -> float:
	return fposmod(progress * 360.0 + 90.0, 360.0)


static func compute_phase(hour: int) -> int:
	if hour >= DAWN_START_HOUR and hour < DAY_START_HOUR:
		return Phase.DAWN
	if hour >= DAY_START_HOUR and hour < DUSK_START_HOUR:
		return Phase.DAY
	if hour >= DUSK_START_HOUR and hour < NIGHT_START_HOUR:
		return Phase.DUSK
	return Phase.NIGHT


static func phase_name(phase_value: int) -> String:
	match phase_value:
		Phase.DAWN:
			return "Alba"
		Phase.DAY:
			return "Giorno"
		Phase.DUSK:
			return "Tramonto"
		_:
			return "Notte"
