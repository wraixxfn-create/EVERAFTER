class_name WorldMap
extends Control
## Full-screen, top-down location map with live player and inhabitant markers.

var player: Node3D
var npc_system: NpcSimulationSystem
var world_extent := 64.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	var panel := Rect2(size * 0.08, size * 0.84)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.025, 0.025, 0.78), true)
	draw_rect(panel, Color(0.08, 0.12, 0.10, 0.98), true)
	draw_rect(panel, Color(0.72, 0.62, 0.40), false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, panel.position + Vector2(24, 38), "MAPPA DEL VILLAGGIO", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.92, 0.83, 0.62))
	draw_string(font, panel.position + Vector2(24, 66), "M o ESC per chiudere", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 0.75, 0.68))
	var map_rect := Rect2(panel.position + Vector2(24, 84), panel.size - Vector2(48, 122))
	draw_rect(map_rect, Color(0.17, 0.22, 0.16), true)
	draw_rect(map_rect, Color(0.54, 0.52, 0.40), false, 1.0)
	# Subtle coordinate grid gives a sense of scale without hiding the markers.
	for i in range(1, 8):
		var f := float(i) / 8.0
		draw_line(map_rect.position + Vector2(map_rect.size.x * f, 0), map_rect.position + Vector2(map_rect.size.x * f, map_rect.size.y), Color(0.85, 0.83, 0.68, 0.09), 1.0)
		draw_line(map_rect.position + Vector2(0, map_rect.size.y * f), map_rect.position + Vector2(map_rect.size.x, map_rect.size.y * f), Color(0.85, 0.83, 0.68, 0.09), 1.0)
	if npc_system != null:
		for npc in npc_system.get_records():
			_draw_marker(map_rect, npc.position, Color(0.94, 0.65, 0.28), 5.0)
	if player != null:
		_draw_marker(map_rect, Vector2(player.global_position.x, player.global_position.z), Color(0.30, 0.78, 1.0), 7.0)
	var legend_y := panel.end.y - 22
	draw_circle(Vector2(panel.position.x + 32, legend_y - 5), 6, Color(0.30, 0.78, 1.0))
	draw_string(font, Vector2(panel.position.x + 45, legend_y), "Tu", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_circle(Vector2(panel.position.x + 105, legend_y - 5), 5, Color(0.94, 0.65, 0.28))
	draw_string(font, Vector2(panel.position.x + 118, legend_y), "Abitanti", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)

func _draw_marker(map_rect: Rect2, world_pos: Vector2, color: Color, radius: float) -> void:
	var extent := maxf(world_extent, 1.0)
	var normalized := (world_pos / (extent * 2.0)) + Vector2(0.5, 0.5)
	var point := map_rect.position + Vector2(normalized.x, 1.0 - normalized.y) * map_rect.size
	if map_rect.has_point(point):
		draw_circle(point, radius + 2.0, Color(0.02, 0.025, 0.02, 0.8))
		draw_circle(point, radius, color)
