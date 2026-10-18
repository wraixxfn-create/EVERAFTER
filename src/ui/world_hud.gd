extends CanvasLayer
## WorldHud — the discreet, always-on medieval overlay.
##
## Shows the name of the game, the simulated day/hour, the current day phase,
## the active simulation speed / pause badge, the name of the area the player
## is standing in, and a subtle centre reticle when the mouse is captured.
##
## Read-only by construction. It never writes to the simulation and never reads
## the world directly: the day comes from the `Game` autoload and the area name
## arrives on `EventBus.area_changed`, which keeps `ui -> core` the only
## dependency this file has (see `docs/ARCHITECTURE.md`).

const HINT_TEXT := (
	"Clic sinistro o F: riprendi il controllo · C: Cronache e salvataggio · "
	+ "P: Pausa · +/-: Velocità"
)

var _area_name := "Campi di Everafter"

@onready var _root: Control = $Root
@onready var _title_label: Label = $Root/Corner/Margin/Lines/TitleLabel
@onready var _day_label: Label = $Root/Corner/Margin/Lines/DayLabel
@onready var _area_label: Label = $Root/Corner/Margin/Lines/AreaLabel
@onready var _phase_badge: Label = $Root/Corner/Margin/Lines/StatusRow/PhaseBadge
@onready var _speed_badge: Label = $Root/Corner/Margin/Lines/StatusRow/SpeedBadge
@onready var _crosshair: Label = $Root/Crosshair
@onready var _hint_label: Label = $Root/Hint


func _ready() -> void:
	_root.theme = UiTheme.shared_theme()
	UiTheme.style_title_label(_title_label, 20)
	EventBus.area_changed.connect(_on_area_changed)
	EventBus.mouse_capture_changed.connect(_on_mouse_capture_changed)
	_title_label.text = Game.config.project_title
	_hint_label.visible = false
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func get_displayed_day_text() -> String:
	return _day_label.text


func get_displayed_area_text() -> String:
	return _area_label.text


func get_displayed_speed_text() -> String:
	return _speed_badge.text


func _refresh() -> void:
	_day_label.text = "Giorno %d · %s" % [Game.get_day(), Game.get_time_text()]
	_area_label.text = "◈ %s" % _area_name
	_phase_badge.text = Game.get_day_phase_name()
	if Game.is_paused():
		_speed_badge.text = "⏸ IN PAUSA"
		_speed_badge.add_theme_color_override("font_color", UiTheme.TEXT_WARN)
	else:
		var scale_val := Game.get_time_scale()
		var arrows := "▶"
		if scale_val >= 9.0:
			arrows = "▶▶▶"
		elif scale_val >= 2.5:
			arrows = "▶▶"
		_speed_badge.text = "%s x%.0f" % [arrows, scale_val]
		_speed_badge.add_theme_color_override("font_color", UiTheme.TEXT_GOOD)


func _on_area_changed(area_name: String) -> void:
	_area_name = area_name


func _on_mouse_capture_changed(is_captured: bool) -> void:
	_hint_label.visible = not is_captured
	if _crosshair != null:
		_crosshair.visible = is_captured
	if not is_captured:
		_hint_label.text = HINT_TEXT
