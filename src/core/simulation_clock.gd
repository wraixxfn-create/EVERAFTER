class_name SimulationClock
extends RefCounted
## Deterministic, integer based clock for the simulated world.
##
## Design contract (see `docs/ARCHITECTURE.md` -> "Tempo simulato"):
## * One logical tick == one simulated minute, so one simulated day lasts
##   exactly [constant MINUTES_PER_DAY] ticks.
## * The clock is a pure counter. It never reads the wall clock, the frame
##   rate, the physics step or the scene tree, therefore two runs fed the same
##   number of ticks always produce exactly the same day and time values.
## * Every derived value is integer arithmetic on [member tick]: no floating
##   point accumulation, therefore no drift between sessions.
##
## Unit tests: `tests/unit/test_simulation_clock.gd`.

## Simulated minutes in one day (24 * 60). Also the number of ticks per day.
const MINUTES_PER_DAY := 1440
const MINUTES_PER_HOUR := 60
const SECONDS_PER_MINUTE := 60
const HOURS_PER_DAY := 24
const DAYS_PER_YEAR := 360

## Elapsed logical ticks since the start of the simulation. Clamped to >= 0.
var tick: int = 0:
	set(value):
		tick = maxi(value, 0)


## Moves the clock forward by [param steps] ticks. Negative values are ignored
## so that a bug in a caller can never rewind the world silently.
func advance(steps: int = 1) -> void:
	tick += maxi(steps, 0)


## Returns the clock to the very beginning of the simulation (day 1, 00:00).
func reset() -> void:
	tick = 0


## Zero based day number: day 0 covers ticks 0..1439.
func get_day_index() -> int:
	return tick / MINUTES_PER_DAY


## Player facing day number, starting from 1 (the world starts on "day 1").
func get_display_day() -> int:
	return get_day_index() + 1


## Minute inside the current day, in the range 0..1439.
func get_minute_of_day() -> int:
	return tick % MINUTES_PER_DAY


## Hour inside the current day, in the range 0..23.
func get_hour() -> int:
	return get_minute_of_day() / MINUTES_PER_HOUR


## Minute inside the current hour, in the range 0..59.
func get_minute() -> int:
	return get_minute_of_day() % MINUTES_PER_HOUR


## Fraction of the current day already elapsed, in the range 0.0..~0.9993.
## Integer tick divided by an integer constant: always the same for a given tick.
func get_day_progress() -> float:
	return float(get_minute_of_day()) / float(MINUTES_PER_DAY)


## Total simulated seconds elapsed since the start of the world.
func get_elapsed_sim_seconds() -> int:
	return tick * SECONDS_PER_MINUTE


## Whole simulated days elapsed (0 during the first day).
func get_elapsed_sim_days() -> int:
	return get_day_index()


## Clock reading formatted as "HH:MM".
func get_time_text() -> String:
	return format_minutes(get_minute_of_day())


## Serialisable snapshot, ready for the future `persistence` module.
func to_dict() -> Dictionary:
	return {"tick": tick}


## Restores a snapshot produced by [method to_dict]. Unknown data resets the clock.
func from_dict(data: Dictionary) -> void:
	tick = int(data.get("tick", 0))


## Readable clock reading.
##
## The method is named `_to_string` on purpose: that is the virtual `Object`
## looks up in a GDScript instance. A method called `to_string()` would *not*
## override anything, it would just shadow a name, and `str(clock)` would keep
## printing `<RefCounted#...>`. Verified against Godot 4.7.2 in
## `tests/unit/test_simulation_clock.gd`.
func _to_string() -> String:
	return "day %d %s (tick %d)" % [get_display_day(), get_time_text(), tick]


## Pure helper: formats a "minutes since midnight" value as "HH:MM".
static func format_minutes(minute_of_day: int) -> String:
	var wrapped := posmod(minute_of_day, MINUTES_PER_DAY)
	return "%02d:%02d" % [wrapped / MINUTES_PER_HOUR, wrapped % MINUTES_PER_HOUR]
