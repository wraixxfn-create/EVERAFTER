extends CanvasLayer
## DiagnosticsHud — the diagnostic overlay toggled with `F1`.
##
## Positioned at the top-centre of the screen so it never overlaps `WorldHud`
## or `EconomyPanel` on the left, nor `NpcPanel` on the right. Read-only by
## design: it never mutates the simulation, it only reads the `Game` autoload
## and listens to `EventBus`.

const TITLE_FORMAT := "%s  ·  %s"

var _status_text := "Avvio in corso…"

@onready var _panel: PanelContainer = $Panel
@onready var _title_label: Label = $Panel/Margins/Lines/TitleLabel
@onready var _day_label: Label = $Panel/Margins/Lines/DayLabel
@onready var _time_label: Label = $Panel/Margins/Lines/TimeLabel
@onready var _sim_label: Label = $Panel/Margins/Lines/SimLabel
@onready var _phase_label: Label = $Panel/Margins/Lines/PhaseLabel
@onready var _perf_label: Label = $Panel/Margins/Lines/PerfLabel
@onready var _status_label: Label = $Panel/Margins/Lines/StatusLabel


func _ready() -> void:
	_panel.theme = UiTheme.shared_theme()
	UiTheme.style_title_label(_title_label, 15)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.time_scale_changed.connect(_on_time_scale_changed)
	EventBus.simulation_paused_changed.connect(_on_paused_changed)
	EventBus.world_ready.connect(_on_world_ready)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hud"):
		visible = not visible


func _refresh() -> void:
	_title_label.text = TITLE_FORMAT % [Game.config.project_title, Game.config.build_label]
	_day_label.text = "Giorno simulato: %d" % Game.get_day()
	_time_label.text = "Ora del mondo: %s" % Game.get_time_text()
	_sim_label.text = "Tick: %d  ·  Velocità: %s" % [Game.get_tick(), _speed_text()]
	_phase_label.text = "Fase: %s" % Game.get_day_phase_name()
	_perf_label.text = "FPS: %d" % int(Engine.get_frames_per_second())
	_status_label.text = _status_text


func _speed_text() -> String:
	if Game.is_paused():
		return "in pausa (P)"
	return "x%.0f" % Game.get_time_scale()


func _on_day_advanced(display_day: int, _minute_of_day: int) -> void:
	_status_text = "È iniziato il giorno %d." % display_day


func _on_time_scale_changed(time_scale: float) -> void:
	_status_text = "Velocità simulazione: x%.0f" % time_scale


func _on_paused_changed(is_paused: bool) -> void:
	if is_paused:
		_status_text = "Simulazione in pausa."
	else:
		_status_text = "Simulazione ripresa."


func _on_world_ready(world_name: String) -> void:
	_status_text = "Mondo pronto: %s" % world_name
