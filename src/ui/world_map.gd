class_name WorldMap
extends Control
## Full-screen top-down map with the live player and inhabitant markers.
##
## Drawn with the same design language as the panels: a single dark card with a
## hairline rim, an overline title, a coordinate grid, warm markers and a legend
## built from keycap-like chips. Purely read-only: it reads `PlayerExplorer`
## position and `NpcSimulationSystem` records on every visible frame.

const MAP_INSET := Vector2(0.07, 0.09)

var player: Node3D
var npc_system: NpcSimulationSystem
var world_extent := 64.0

var _frame: StyleBoxFlat
var _map_frame: StyleBoxFlat
var _chip_frame: StyleBoxFlat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_frame = UiTheme.make_panel_style(
		Color(0.035, 0.033, 0.030, 0.97), UiTheme.BORDER_BRASS, 10, 0.0, 0.0
	)
	_frame.shadow_size = 28
	_map_frame = UiTheme.make_panel_style(
		Color(0.062, 0.075, 0.060, 0.98), UiTheme.BORDER_SUBTLE, 6, 0.0, 0.0
	)
	_map_frame.shadow_size = 0
	_chip_frame = UiTheme.make_inset_style(UiTheme.BG_BADGE, UiTheme.BORDER_SUBTLE, 3, 0.0, 0.0)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.012, 0.014, 0.012, 0.84), true)
	var panel := Rect2(size * MAP_INSET, size * (Vector2.ONE - MAP_INSET * 2.0))
	draw_style_box(_frame, panel)
	var pad := 30.0
	_draw_header(panel, pad)
	var map_rect := Rect2(
		panel.position + Vector2(pad, 92.0),
		panel.size - Vector2(pad * 2.0, 92.0 + pad + 54.0)
	)
	draw_style_box(_map_frame, map_rect)
	_draw_grid(map_rect)
	if npc_system != null:
		for npc in npc_system.get_records():
			_draw_marker(map_rect, npc.position, Color(0.86, 0.66, 0.40), 4.0)
	if player != null:
		_draw_player(map_rect, Vector2(player.global_position.x, player.global_position.z))
	_draw_legend(panel, map_rect, pad)
	_draw_close_hint(panel, pad)


func _draw_header(panel: Rect2, pad: float) -> void:
	var origin := panel.position + Vector2(pad, 34.0)
	draw_string(
		UiTheme.overline_font(),
		origin,
		"MAPPA DEL VILLAGGIO",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		10,
		UiTheme.TEXT_GOLD_DIM
	)
	draw_string(
		UiTheme.header_font(),
		origin + Vector2(0, 32),
		"Everafter",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		26,
		UiTheme.TEXT_PARCHMENT
	)
	draw_string(
		UiTheme.body_font(),
		origin + Vector2(112, 31),
		"le aree del villaggio e i suoi abitanti",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		UiTheme.TEXT_MUTED
	)
	var rule_y := origin.y + 50.0
	draw_line(
		Vector2(panel.position.x + pad, rule_y),
		Vector2(panel.end.x - pad, rule_y),
		UiTheme.BORDER_SUBTLE,
		1.0
	)


func _draw_grid(map_rect: Rect2) -> void:
	for i in range(1, 8):
		var f := float(i) / 8.0
		var alpha := 0.05 if i % 2 == 0 else 0.025
		var line_color := Color(0.90, 0.86, 0.74, alpha)
		var x := map_rect.position.x + map_rect.size.x * f
		var y := map_rect.position.y + map_rect.size.y * f
		draw_line(Vector2(x, map_rect.position.y), Vector2(x, map_rect.end.y), line_color, 1.0)
		draw_line(Vector2(map_rect.position.x, y), Vector2(map_rect.end.x, y), line_color, 1.0)
	draw_rect(map_rect, Color(0.90, 0.86, 0.74, 0.06), false, 1.0)


func _draw_marker(map_rect: Rect2, world_pos: Vector2, color: Color, radius: float) -> void:
	var point := _map_point(map_rect, world_pos)
	if not map_rect.has_point(point):
		return
	draw_circle(point, radius + 4.0, Color(0.02, 0.025, 0.02, 0.65))
	draw_circle(point, radius, color)
	draw_arc(point, radius + 2.5, 0.0, TAU, 20, Color(color.r, color.g, color.b, 0.35), 1.0)


func _draw_player(map_rect: Rect2, world_pos: Vector2) -> void:
	var point := _map_point(map_rect, world_pos)
	if not map_rect.has_point(point):
		return
	var color := Color(0.42, 0.78, 0.96)
	draw_circle(point, 9.0, Color(color.r, color.g, color.b, 0.16))
	draw_arc(point, 9.0, 0.0, TAU, 28, Color(color.r, color.g, color.b, 0.55), 1.0)
	draw_circle(point, 4.0, color)
	draw_circle(point, 1.6, UiTheme.TEXT_PARCHMENT)


func _draw_legend(panel: Rect2, map_rect: Rect2, pad: float) -> void:
	var y := map_rect.end.y + 30.0
	var x := panel.position.x + pad
	x = _draw_legend_item(x, y, Color(0.42, 0.78, 0.96), "Tu")
	x = _draw_legend_item(x + 26.0, y, Color(0.86, 0.66, 0.40), "Abitanti")
	draw_string(
		UiTheme.body_font(),
		Vector2(x + 26.0, y + 4.0),
		"Nord in alto · scala 1:1 sul villaggio",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		UiTheme.TEXT_MUTED
	)


func _draw_legend_item(x: float, y: float, color: Color, text: String) -> float:
	draw_circle(Vector2(x + 4.0, y - 4.0), 4.0, color)
	draw_string(
		UiTheme.body_font(),
		Vector2(x + 14.0, y),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		UiTheme.TEXT_SECONDARY
	)
	return x + 14.0 + UiTheme.body_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x


func _draw_close_hint(panel: Rect2, pad: float) -> void:
	var text := "M  o  Esc  per chiudere"
	var text_width := UiTheme.body_font().get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11
	).x
	var rect := Rect2(
		Vector2(panel.end.x - pad - text_width - 20.0, panel.end.y - pad - 22.0),
		Vector2(text_width + 20.0, 22.0)
	)
	draw_style_box(_chip_frame, rect)
	draw_string(
		UiTheme.body_font(),
		rect.position + Vector2(10.0, 15.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		UiTheme.TEXT_MUTED
	)


func _map_point(map_rect: Rect2, world_pos: Vector2) -> Vector2:
	var extent := maxf(world_extent, 1.0)
	var normalized := (world_pos / (extent * 2.0)) + Vector2(0.5, 0.5)
	return map_rect.position + Vector2(normalized.x, 1.0 - normalized.y) * map_rect.size
