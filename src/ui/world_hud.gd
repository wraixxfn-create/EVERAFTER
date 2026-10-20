extends CanvasLayer
## WorldHud — the quiet, always-on overlay of the village.
##
## One card in the top-left corner answers the three questions a player asks
## without thinking about it: *when am I, where am I, and is time running?*
## Everything else (economy, inhabitants, map, chronicle) lives in its own panel.
##
## Read-only by construction. It never writes to the simulation and never reads
## the world directly: the day comes from the `Game` autoload and the area name
## arrives on `EventBus.area_changed`, so `ui -> core` stays the only dependency
## this file has (see `docs/ARCHITECTURE.md`).
##
## The card measures itself from its content (`_fit`) instead of using a magic
## fixed height, which is what used to leave labels hanging outside the panel
## when the system font stack resolved to taller metrics.

const CARD_WIDTH := 312.0

var _area_name := "Campi di Everafter"
var _last_clock_text := ""
var _last_phase_text := ""
var _last_speed_key := ""

@onready var _root: Control = $Root
@onready var _status: PanelContainer = $Root/Status
@onready var _title_label: Label = $Root/Status/Pad/Lines/TitleLabel
@onready var _day_label: Label = $Root/Status/Pad/Lines/DayLabel
@onready var _area_label: Label = $Root/Status/Pad/Lines/AreaLabel
@onready var _phase_badge: Label = $Root/Status/Pad/Lines/StatusRow/PhaseBadge
@onready var _speed_badge: Label = $Root/Status/Pad/Lines/StatusRow/SpeedBadge
@onready var _crosshair: Control = $Root/Crosshair
@onready var _hint_bar: PanelContainer = $Root/Hint


func _ready() -> void:
	_root.theme = UiTheme.shared_theme()
	_status.add_theme_stylebox_override(
		"panel",
		UiTheme.make_panel_style(UiTheme.BG_HUD, UiTheme.BORDER_BRASS, UiTheme.PANEL_RADIUS, 18.0, 16.0)
	)
	_hint_bar.add_theme_stylebox_override(
		"panel",
		UiTheme.make_panel_style(UiTheme.BG_HUD, UiTheme.BORDER_BRASS, UiTheme.PANEL_RADIUS, 14.0, 9.0)
	)
	UiTheme.style_title_label(_title_label, 19, UiTheme.TEXT_GOLD)
	UiTheme.style_title_label(_day_label, 22, UiTheme.TEXT_PARCHMENT)
	UiTheme.style_body_label(_area_label, 12, UiTheme.TEXT_MUTED)
	UiTheme.style_chip(_phase_badge, UiTheme.TEXT_GOLD)
	UiTheme.style_chip(_speed_badge, UiTheme.TEXT_GOOD)
	for label in $Root/Hint/Pad/Row.get_children():
		if not label is Label:
			continue
		if String(label.name).begins_with("Key"):
			UiTheme.style_keycap(label)
		else:
			UiTheme.style_body_label(label, 12, UiTheme.TEXT_MUTED)
	EventBus.area_changed.connect(_on_area_changed)
	EventBus.mouse_capture_changed.connect(_on_mouse_capture_changed)
	_title_label.text = Game.config.project_title
	_hint_bar.visible = false
	_crosshair.visible = true
	_refresh()
	_fit.call_deferred()
	get_viewport().size_changed.connect(_fit)


func get_displayed_day_text() -> String:
	return _day_label.text


func get_displayed_area_text() -> String:
	return _area_label.text


func get_displayed_speed_text() -> String:
	return _speed_badge.text


## Sizes the status card and the bottom hint bar from their own content.
func _fit() -> void:
	if not is_inside_tree():
		return
	var status_min := _status.get_combined_minimum_size()
	_status.offset_right = _status.offset_left + maxf(status_min.x, CARD_WIDTH)
	_status.offset_bottom = _status.offset_top + status_min.y
	var hint_min := _hint_bar.get_combined_minimum_size()
	var viewport_width := get_viewport().get_visible_rect().size.x
	var hint_width := minf(hint_min.x, viewport_width - 2.0 * UiTheme.SCREEN_MARGIN)
	_hint_bar.offset_left = -hint_width * 0.5
	_hint_bar.offset_right = hint_width * 0.5
	_hint_bar.offset_top = -UiTheme.SCREEN_MARGIN - hint_min.y
	_hint_bar.offset_bottom = -UiTheme.SCREEN_MARGIN


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	# Only touch the labels when the text actually changes: `_process` runs every
	# frame and rebuilding identical strings would allocate for no reason.
	var clock_text := "Giorno %d · %s" % [Game.get_day(), Game.get_time_text()]
	if clock_text != _last_clock_text:
		_last_clock_text = clock_text
		_day_label.text = clock_text
	var phase_text := Game.get_day_phase_name()
	if phase_text != _last_phase_text:
		_last_phase_text = phase_text
		_phase_badge.text = phase_text
	var speed_key := _speed_key()
	if speed_key != _last_speed_key:
		_last_speed_key = speed_key
		_apply_speed_badge()


func _speed_key() -> String:
	if Game.is_paused():
		return "paused"
	return "x%.0f" % Game.get_time_scale()


func _apply_speed_badge() -> void:
	if Game.is_paused():
		_speed_badge.text = "PAUSA"
		UiTheme.style_chip(_speed_badge, UiTheme.TEXT_WARN)
		return
	var scale_val := Game.get_time_scale()
	_speed_badge.text = "×%d" % int(round(scale_val))
	UiTheme.style_chip(_speed_badge, UiTheme.TEXT_GOOD if scale_val >= 2.5 else UiTheme.TEXT_CALM)


func _on_area_changed(area_name: String) -> void:
	_area_name = area_name
	_area_label.text = area_name


func _on_mouse_capture_changed(is_captured: bool) -> void:
	_hint_bar.visible = not is_captured
	_crosshair.visible = is_captured
