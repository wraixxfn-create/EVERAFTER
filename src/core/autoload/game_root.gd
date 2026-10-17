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
var save_manager: SaveManager = null
var chronicle_book: ChronicleBook = null
var chronicle_watcher: ChronicleWatcher = null
var offline_catchup: OfflineCatchup = null
var _offline_summary: Dictionary = {}

var _time_scale_index: int = 0
var _day_cycle: DayCycleSystem = null
var _npc_system: NpcSimulationSystem = null
var _economy_system: EconomySystem = null
var _social_system: SocialSystem = null
var _world_ready: bool = false
var _autosave_interval_ticks: int = 720  # 12 sim hours
var _ticks_since_save: int = 0


func _ready() -> void:
	config = GameConfig.load_or_default()
	_report_config_problems(config.validate())

	loop = SimulationLoop.new()
	loop.tick_seconds = maxf(config.logic_tick_seconds, 0.001)
	loop.max_steps_per_frame = config.max_steps_per_frame
	loop.time_scale = config.initial_time_scale()
	_time_scale_index = config.clamped_time_scale_index(config.default_time_scale_index)

	save_manager = SaveManager.new(config)
	save_manager.loop = loop
	chronicle_book = ChronicleBook.new(config.chronicle_max_entries)

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
	var previous_tick := loop.clock.tick
	loop.update(delta)
	var ticks_done := loop.clock.tick - previous_tick
	_ticks_since_save += maxi(ticks_done, 0)
	if _world_ready and chronicle_watcher != null and _npc_system != null:
		chronicle_watcher.observe(loop.clock.tick, loop.clock)
	# Autosave every _autosave_interval_ticks (12 sim hours).
	if _world_ready and save_manager != null and _ticks_since_save >= _autosave_interval_ticks:
		_ticks_since_save = 0
		save_manager.save_to_file()


## Runtime shortcuts for the simulation speed. Bound in `project.godot`
## (`sim_pause`, `sim_speed_up`, `sim_speed_down`) and documented in the README.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("sim_pause"):
		toggle_pause()
	elif event.is_action_pressed("sim_speed_up"):
		step_time_scale(1)
	elif event.is_action_pressed("sim_speed_down"):
		step_time_scale(-1)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			# Best-effort save on quit. Failures are logged but do not block
			# the window from closing.
			if _world_ready and save_manager != null:
				save_manager.save_to_file()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED:
			# Mobile/web pause: also save defensively.
			if _world_ready and save_manager != null:
				save_manager.save_to_file()


# --- read-only facade used by the UI and by the world ------------------------


func get_clock() -> SimulationClock:
	return loop.clock


func get_day() -> int:
	return loop.clock.get_display_day()


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


func get_social_system() -> SocialSystem:
	return _social_system


func get_chronicle_book() -> ChronicleBook:
	return chronicle_book


func get_save_manager() -> SaveManager:
	return save_manager


func get_offline_summary() -> Dictionary:
	return _offline_summary


func get_last_save_info() -> Dictionary:
	if save_manager == null:
		return {"exists": false}
	var real_str := ""
	if save_manager.last_save_real_time > 0:
		real_str = _format_real_time(save_manager.last_save_real_time)
	return {
		"exists": save_manager.has_save_file(),
		"real_time": save_manager.last_save_real_time,
		"real_time_text": real_str,
		"sim_day": save_manager.last_save_simulated_day,
		"sim_time_text": save_manager.last_save_simulated_time_text,
		"population": save_manager.last_save_population,
	}


# --- commands ---------------------------------------------------------------


## Registers the inhabitant simulation once the world has built its places.
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
	_wire_persistence_systems()
	return true


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
	_wire_persistence_systems()
	return true


func set_social_system(system: SocialSystem) -> bool:
	if system == null:
		return false
	if _social_system == system:
		return true
	if _social_system != null:
		push_warning("Game: a social system is already registered.")
		return false
	_social_system = system
	loop.register_system(system)
	EventBus.social_system_ready.emit()
	_wire_persistence_systems()
	return true


## Called by MainWorld once every system is in place. If a save exists it is
## loaded here, and offline catch-up is applied immediately after.
func world_build_finished() -> Dictionary:
	_wire_persistence_systems()
	_world_ready = true
	EventBus.world_ready.emit("MainWorld")
	# Seed the watcher's baselines now that systems are populated and before
	# any load or catch-up changes them further.
	if chronicle_watcher != null:
		chronicle_watcher.initialize(loop.clock)
	var load_result := {"loaded": false, "message": "Nuovo villaggio.", "error": 0}
	if save_manager != null and save_manager.has_save_file():
		var err_code: int = save_manager.load_from_file()[0]
		if err_code == SaveManager.Error.OK:
			load_result["loaded"] = true
			load_result["message"] = save_manager.last_load_status
			load_result["error"] = 0
			var catchup := _apply_offline_catchup()
			load_result["catchup"] = catchup
		else:
			load_result["error"] = err_code
			load_result["message"] = "Salvataggio non caricato: %s." % SaveManager.error_label(err_code)
			GameLog.warning(TAG, load_result["message"])
	else:
		# No prior save: the world begins now. Record nothing new — the
		# watcher already wrote the "world begins" milestone.
		pass
	return load_result


## Explicit save. Returns the SaveManager error code (0 on success).
func request_save() -> int:
	if save_manager == null:
		return SaveManager.Error.WORLD_NOT_READY
	var err := save_manager.save_to_file()
	if err == SaveManager.Error.OK:
		EventBus.save_performed.emit()
	return err


## Returns the population size saved on disk, or the default from config when
## no save exists. Used by MainWorld so it builds the right number of NPCs
## before the systems are registered.
func get_saved_population_size() -> int:
	if save_manager == null:
		return config.npc_population_size
	var saved := save_manager.read_saved_population()
	if saved <= 0:
		return config.npc_population_size
	return clampi(saved, 0, NpcRoster.MAX_POPULATION)


## Explicit time advancement, independent of frames.
func advance_simulation(ticks: int) -> void:
	loop.run_ticks(maxi(ticks, 0))


func set_time_scale_index(index: int) -> void:
	var presets := config.validated_time_scale_presets()
	_time_scale_index = config.clamped_time_scale_index(index)
	loop.set_time_scale(presets[_time_scale_index])


func step_time_scale(direction: int) -> void:
	var presets := config.validated_time_scale_presets()
	var next_index := posmod(_time_scale_index + signi(direction), presets.size())
	set_time_scale_index(next_index)


func toggle_pause() -> void:
	loop.toggle_paused()


# --- internals --------------------------------------------------------------


func _wire_persistence_systems() -> void:
	if save_manager == null:
		return
	save_manager.npc_system = _npc_system
	save_manager.economy_system = _economy_system
	save_manager.social_system = _social_system
	save_manager.chronicle_book = chronicle_book
	if _npc_system != null and _economy_system != null and _social_system != null \
			and chronicle_book != null and chronicle_watcher == null:
		chronicle_watcher = ChronicleWatcher.new(
			chronicle_book, _npc_system, _economy_system, _social_system
		)
		save_manager.chronicle_watcher = chronicle_watcher
		if offline_catchup == null:
			offline_catchup = OfflineCatchup.new(loop, chronicle_watcher, chronicle_book, config)
			offline_catchup.max_offline_simulated_days = config.max_offline_simulated_days
			offline_catchup.offline_time_scale = config.offline_time_scale


func _apply_offline_catchup() -> Dictionary:
	if offline_catchup == null or save_manager == null:
		return {"message": "Catch-up non disponibile."}
	var ts := save_manager.last_save_real_time
	var summary := offline_catchup.run(ts)
	_offline_summary = summary
	# After a catch-up the save timestamp on disk no longer matches "now",
	# but we do NOT auto-save here: the player should see the result first.
	return summary


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


## Very small wall-clock formatter for the UI (no seconds, local time).
func _format_real_time(unix_seconds: int) -> String:
	if unix_seconds <= 0:
		return ""
	var dt := Time.get_datetime_dict_from_unix_time(unix_seconds)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(dt.get("year", 0)),
		int(dt.get("month", 0)),
		int(dt.get("day", 0)),
		int(dt.get("hour", 0)),
		int(dt.get("minute", 0)),
	]
