class_name SimulationLoop
extends RefCounted
## Fixed-timestep driver for the whole simulation.
##
## Rendering time and simulation time are different clocks on purpose:
## * the renderer calls [method update] with the real `delta` of the frame;
## * the loop converts that into a whole number of fixed logical ticks of
##   [member tick_seconds] each and advances [member clock] tick by tick;
## * leftover time is kept in an accumulator, so no simulated time is lost and
##   none is duplicated.
##
## Consequences that matter for this project:
## * the outcome depends on the *number of ticks*, never on the frame rate:
##   a machine running at 144 fps and one running at 30 fps see the same world;
## * pausing ([member paused]) or slowing down ([member time_scale]) only
##   changes how many ticks are produced per second;
## * catching up on time spent while the player was away is just
##   `for i in ticks: step_once()`, with no rendering involved at all.
##
## Unit tests: `tests/unit/test_simulation_loop.gd`.

signal day_advanced(display_day: int)
signal time_scale_changed(time_scale: float)
signal paused_changed(is_paused: bool)

const DEFAULT_TICK_SECONDS := 0.05
const DEFAULT_MAX_STEPS_PER_FRAME := 12
## Upper bound for a single `delta` accepted by the accumulator (1 real second).
const MAX_DELTA := 1.0

var clock := SimulationClock.new()

## Speed multiplier: 1.0 = one tick every [member tick_seconds] real seconds.
var time_scale: float = 1.0
## Real seconds covered by one logical tick (at speed x1).
var tick_seconds: float = DEFAULT_TICK_SECONDS
## Ticks executed at most in one frame; extra backlog is dropped.
var max_steps_per_frame: int = DEFAULT_MAX_STEPS_PER_FRAME
## Hard stop. While paused [method update] does nothing at all.
var paused: bool = false

var _systems: Array[SimulationSystem] = []
var _accumulator: float = 0.0
var _last_display_day: int = 1


## Registers a system. Registration order is the execution order, and it is
## part of the deterministic contract (documented, not accidental).
func register_system(system: SimulationSystem) -> void:
	if system == null:
		push_error("SimulationLoop: refusing to register a null system.")
		return
	if get_system(system.get_system_name()) != null:
		push_error("SimulationLoop: system '%s' is already registered." % system.get_system_name())
		return
	_systems.append(system)


func get_system(system_name: String) -> SimulationSystem:
	for system in _systems:
		if system.get_system_name() == system_name:
			return system
	return null


func get_system_count() -> int:
	return _systems.size()


func get_system_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for system in _systems:
		names.append(system.get_system_name())
	return names


## Converts real time into logical ticks. Returns the number of ticks executed.
func update(delta: float) -> int:
	if paused or time_scale <= 0.0:
		return 0
	_accumulator += clampf(delta, 0.0, MAX_DELTA) * time_scale
	var steps := 0
	while _accumulator >= tick_seconds and steps < max_steps_per_frame:
		step_once()
		_accumulator -= tick_seconds
		steps += 1
	if _accumulator > tick_seconds * float(max_steps_per_frame):
		# A frame took too long: drop the backlog instead of simulating it in a
		# burst (spiral of death guard). The lost time is reported by the caller
		# through the returned step count.
		_accumulator = 0.0
	return steps


## Advances the world by exactly one tick: clock first, then systems in order.
func step_once() -> void:
	clock.advance(1)
	for system in _systems:
		if system.enabled:
			system.on_tick(clock.tick, clock)
	var display_day := clock.get_display_day()
	if display_day != _last_display_day:
		_last_display_day = display_day
		day_advanced.emit(display_day)


## Places the world at a given minute of day 1 and initialises every system
## with that time, so the first rendered frame already matches the clock.
func set_start_time(minute_of_day: int) -> void:
	clock.tick = clampi(minute_of_day, 0, SimulationClock.MINUTES_PER_DAY - 1)
	_accumulator = 0.0
	_last_display_day = clock.get_display_day()
	for system in _systems:
		if system.enabled:
			system.on_tick(clock.tick, clock)


## Runs [param ticks] ticks without any real time involved. This is the entry
## point that the future "time passed while you were away" feature will use.
func run_ticks(ticks: int) -> void:
	for _i in maxi(ticks, 0):
		step_once()


func set_time_scale(value: float) -> void:
	var clamped := maxf(value, 0.0)
	if is_equal_approx(clamped, time_scale):
		return
	time_scale = clamped
	time_scale_changed.emit(time_scale)


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	paused_changed.emit(paused)


func toggle_paused() -> void:
	set_paused(not paused)


## Empties the accumulator and rewinds the clock to day 1, 00:00.
func reset() -> void:
	_accumulator = 0.0
	clock.reset()
	_last_display_day = 1
	for system in _systems:
		system.reset()


## Whole-loop snapshot: clock + every system, keyed by system name.
func to_dict() -> Dictionary:
	var systems_data := {}
	for system in _systems:
		systems_data[system.get_system_name()] = system.to_dict()
	return {
		"clock": clock.to_dict(),
		"time_scale": time_scale,
		"systems": systems_data,
	}


## Restores a snapshot produced by [method to_dict].
func from_dict(data: Dictionary) -> void:
	_accumulator = 0.0
	clock.from_dict(data.get("clock", {}))
	_last_display_day = clock.get_display_day()
	set_time_scale(float(data.get("time_scale", time_scale)))
	var systems_data: Dictionary = data.get("systems", {})
	for system in _systems:
		if systems_data.has(system.get_system_name()):
			system.from_dict(systems_data[system.get_system_name()])
