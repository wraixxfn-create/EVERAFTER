extends Node
## Game — autoload singleton (registered as `Game` in project.godot).
##
## Single owner of "how the simulation runs": it loads the configuration,
## builds the [SimulationLoop], registers the systems that exist today and
## feeds the loop with real time. Everything else (world, UI, future modules)
## reads state from here instead of owning its own clock.
##
## Autoload order matters and is declared in `project.godot`: `EventBus` first,
## then `Game`, because `Game` publishes on the bus during `_ready()`.

const TAG := "Game"

var config: GameConfig = GameConfig.new()
var loop: SimulationLoop = SimulationLoop.new()

var _time_scale_index: int = 0
var _day_cycle: DayCycleSystem = null
var _npc_system: NpcSimulationSystem = null
var _economy_system: EconomySystem = null


func _ready() -> void:
	config = GameConfig.load_or_default()
	_report_config_problems(config.validate())

	loop = SimulationLoop.new()
	loop.tick_seconds = maxf(config.logic_tick_seconds, 0.001)
	loop.max_steps_per_frame = config.max_steps_per_frame
	loop.time_scale = config.initial_time_scale()
	_time_scale_index = config.clamped_time_scale_index(config.default_time_scale_index)

	_day_cycle = DayCycleSystem.new()
	loop.register_system(_day_cycle)
	loop.set_start_time(config.start_minute_of_day)

	loop.day_advanced.connect(_on_day_advanced)
	loop.time_scale_changed.connect(_on_time_scale_changed)
	loop.paused_changed.connect(_on_paused_changed)

	GameLog.info(
		TAG,
		(
			"ready — %s %s | start=%s | tick=%.3fs | presets=%s | systems=%s"
			% [
				config.project_title,
				config.build_label,
				loop.clock.get_time_text(),
				loop.tick_seconds,
				config.validated_time_scale_presets(),
				loop.get_system_names(),
			]
		)
	)


## Real time in, logical ticks out. This is the only place where wall clock
## time touches the simulation.
func _process(delta: float) -> void:
	loop.update(delta)


## Runtime shortcuts for the simulation speed. Bound in `project.godot`
## (`sim_pause`, `sim_speed_up`, `sim_speed_down`) and documented in the README.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("sim_pause"):
		toggle_pause()
	elif event.is_action_pressed("sim_speed_up"):
		step_time_scale(1)
	elif event.is_action_pressed("sim_speed_down"):
		step_time_scale(-1)


# --- read-only facade used by the UI and by the world ------------------------


func get_clock() -> SimulationClock:
	return loop.clock


## Player facing day number, starting from 1.
func get_day() -> int:
	return loop.clock.get_display_day()


## "HH:MM" reading of the simulated clock.
func get_time_text() -> String:
	return loop.clock.get_time_text()


func get_tick() -> int:
	return loop.clock.tick


func get_time_scale() -> float:
	return loop.time_scale


func get_time_scale_index() -> int:
	return _time_scale_index


func is_paused() -> bool:
	return loop.paused


func get_day_cycle() -> DayCycleSystem:
	return _day_cycle


func get_day_phase_name() -> String:
	if _day_cycle == null:
		return "-"
	return _day_cycle.get_phase_name()


func get_daylight_factor() -> float:
	if _day_cycle == null:
		return 0.0
	return _day_cycle.get_daylight_factor()


func get_npc_system() -> NpcSimulationSystem:
	return _npc_system


func get_economy_system() -> EconomySystem:
	return _economy_system


# --- commands ---------------------------------------------------------------


## Registers the inhabitant simulation once the world has built its places.
## Kept here instead of in the world so that `Game` remains the single owner of
## the loop: the 3D scene injects data, it does not drive time.
func set_npc_system(system: NpcSimulationSystem) -> bool:
	if system == null:
		return false
	if _npc_system == system:
		return true
	if _npc_system != null:
		push_warning("Game: an NPC system is already registered.")
		return false
	_npc_system = system
	loop.register_system(system)
	EventBus.npc_system_ready.emit()
	return true


## Registers the local economy system once the inhabitants have been created.
func set_economy_system(system: EconomySystem) -> bool:
	if system == null:
		return false
	if _economy_system == system:
		return true
	if _economy_system != null:
		push_warning("Game: an economy system is already registered.")
		return false
	_economy_system = system
	loop.register_system(system)
	EventBus.economy_system_ready.emit()
	return true


## Explicit time advancement, independent of frames. Used by the integration
## tests today and by the future "time passed while you were away" feature.
func advance_simulation(ticks: int) -> void:
	loop.run_ticks(maxi(ticks, 0))


func set_time_scale_index(index: int) -> void:
	var presets := config.validated_time_scale_presets()
	_time_scale_index = config.clamped_time_scale_index(index)
	loop.set_time_scale(presets[_time_scale_index])


## [param direction] > 0 speeds the world up, < 0 slows it down, wrapping
## around the list of presets.
func step_time_scale(direction: int) -> void:
	var presets := config.validated_time_scale_presets()
	var next_index := posmod(_time_scale_index + signi(direction), presets.size())
	set_time_scale_index(next_index)


func toggle_pause() -> void:
	loop.toggle_paused()


# --- internals --------------------------------------------------------------


func _report_config_problems(problems: PackedStringArray) -> void:
	for problem in problems:
		GameLog.warning(TAG, "config problem: %s" % problem)


func _on_day_advanced(display_day: int) -> void:
	EventBus.day_advanced.emit(display_day, loop.clock.get_minute_of_day())
	GameLog.info(TAG, "day %d begins (%s)" % [display_day, loop.clock.get_time_text()])


func _on_time_scale_changed(time_scale: float) -> void:
	EventBus.time_scale_changed.emit(time_scale)


func _on_paused_changed(is_paused: bool) -> void:
	EventBus.simulation_paused_changed.emit(is_paused)
