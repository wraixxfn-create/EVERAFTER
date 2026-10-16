extends CanvasLayer
## WorldHud — the discreet, always-on overlay required by this phase.
##
## It shows exactly three things: the name of the game, the simulated day and
## the name of the area the player is standing in. Nothing else: no numbers, no
## panels, no menus. The diagnostics overlay (`DiagnosticsHud`, toggled with
## `F1`) is where the technical readouts live, so this file can stay small.
##
## Read-only by construction. It never writes to the simulation and never reads
## the world directly: the day comes from the `Game` autoload and the area name
## arrives on `EventBus.area_changed`, which keeps `ui -> core` the only
## dependency this file has (see `docs/ARCHITECTURE.md`).

var _area_name := "Campi di Everafter"

@onready var _title_label: Label = $Root/Corner/Margin/Lines/TitleLabel
@onready var _day_label: Label = $Root/Corner/Margin/Lines/DayLabel
@onready var _area_label: Label = $Root/Corner/Margin/Lines/AreaLabel
@onready var _hint_label: Label = $Root/Hint


func _ready() -> void:
	EventBus.area_changed.connect(_on_area_changed)
	EventBus.mouse_capture_changed.connect(_on_mouse_capture_changed)
	_title_label.text = Game.config.project_title
	_hint_label.visible = false
	_refresh()


## Two labels change at most once per simulated minute, so refreshing every
## frame is cheaper than wiring a signal per value and can never go stale.
func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	_day_label.text = "Giorno %d · %s" % [Game.get_day(), Game.get_time_text()]
	_area_label.text = _area_name


func _on_area_changed(area_name: String) -> void:
	_area_name = area_name


func _on_mouse_capture_changed(is_captured: bool) -> void:
	_hint_label.visible = not is_captured
