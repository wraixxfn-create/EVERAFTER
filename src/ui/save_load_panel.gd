class_name SaveLoadPanel
extends CanvasLayer
## Overlay panel for save, load and chronicle consultation.
##
## The panel is toggled with the `open_menu` action (C key) and starts
## hidden. It shows:
## * Last save metadata (real date, simulated day, population).
## * Buttons to Save, Load (with overwrite confirmation on Save) and Close.
## * A scrollable chronicle list of real entries from `ChronicleBook`, with a
##   category filter and a day filter (all / current day).
##
## Built entirely in code to avoid .tscn churn and stay aligned with the rest
## of the UI's lightweight style. The panel never drives the simulation; it
## only calls `Game.request_save()` and reads state from Game/ChronicleBook.

const PANEL_WIDTH := 520
const PANEL_HEIGHT := 620
const ENTRIES_PER_PAGE := 200

var _visible: bool = false
var _category_filter: int = -1
var _day_filter: int = 0
var _root: Control = null
var _panel: PanelContainer = null
var _save_status_label: Label = null
var _message_label: Label = null
var _entries_container: VBoxContainer = null
var _category_button: OptionButton = null
var _day_button: OptionButton = null
var _save_button: Button = null
var _load_button: Button = null
var _new_button: Button = null
var _confirm_dialog: ConfirmationDialog = null
var _confirm_save: bool = false


func _ready() -> void:
	set_layer(8)
	_build_ui()
	EventBus.save_performed.connect(_on_save_performed)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _visible:
		_hide_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_menu"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _visible:
		_hide_panel()
	else:
		_show_panel()


func _show_panel() -> void:
	_visible = true
	_root.visible = true
	_refresh()
	# Release mouse so the panel is clickable.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _hide_panel() -> void:
	_visible = false
	_root.visible = false


func _build_ui() -> void:
	# Background dimmer.
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.02, 0.03, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_background_input)
	_root.add_child(bg)
	add_child(_root)
	# Panel: sized explicitly and centered via anchors. On a viewport
	# smaller than PANEL_WIDTH x PANEL_HEIGHT the panel overflows (same
	# approach used by EconomyPanel in this project); on a 1600x900 window
	# it is centred.
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -PANEL_WIDTH * 0.5
	_panel.offset_top = -PANEL_HEIGHT * 0.5
	_panel.offset_right = PANEL_WIDTH * 0.5
	_panel.offset_bottom = PANEL_HEIGHT * 0.5
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.04, 0.05, 0.07, 0.92)
	box_style.border_width_left = 1
	box_style.border_width_top = 1
	box_style.border_width_right = 1
	box_style.border_width_bottom = 1
	box_style.border_color = Color(0.45, 0.40, 0.28, 0.8)
	box_style.corner_radius_top_left = 6
	box_style.corner_radius_top_right = 6
	box_style.corner_radius_bottom_right = 6
	box_style.corner_radius_bottom_left = 6
	_panel.add_theme_stylebox_override("panel", box_style)
	_root.add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	# Title row.
	var title := Label.new()
	title.text = "CRONACHE E SALVATAGGIO"
	title.add_theme_color_override("font_color", Color(0.93, 0.86, 0.66, 1.0))
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	_save_status_label = Label.new()
	_save_status_label.add_theme_font_size_override("font_size", 12)
	_save_status_label.add_theme_color_override("font_color", Color(0.78, 0.74, 0.62, 1.0))
	_save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_save_status_label)
	# Filter row.
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	vbox.add_child(filter_row)
	var cat_label := Label.new()
	cat_label.text = "Categoria:"
	cat_label.add_theme_font_size_override("font_size", 12)
	filter_row.add_child(cat_label)
	_category_button = OptionButton.new()
	_category_button.add_item("Tutte")
	_category_button.set_item_metadata(0, -1)
	_category_button.add_item("Produzione")
	_category_button.set_item_metadata(1, ChronicleEntry.Category.PRODUCTION)
	_category_button.add_item("Carenza")
	_category_button.set_item_metadata(2, ChronicleEntry.Category.SHORTAGE)
	_category_button.add_item("Aiuto")
	_category_button.set_item_metadata(3, ChronicleEntry.Category.HELP)
	_category_button.add_item("Relazione")
	_category_button.set_item_metadata(4, ChronicleEntry.Category.RELATIONSHIP)
	_category_button.add_item("Progetto")
	_category_button.set_item_metadata(5, ChronicleEntry.Category.PROJECT)
	_category_button.add_item("Tappa")
	_category_button.set_item_metadata(6, ChronicleEntry.Category.MILESTONE)
	_category_button.add_item("Sistema")
	_category_button.set_item_metadata(7, ChronicleEntry.Category.SYSTEM)
	_category_button.item_selected.connect(_on_category_selected)
	filter_row.add_child(_category_button)
	var day_label := Label.new()
	day_label.text = "Giorno:"
	day_label.add_theme_font_size_override("font_size", 12)
	filter_row.add_child(day_label)
	_day_button = OptionButton.new()
	_day_button.add_item("Tutti")
	_day_button.set_item_metadata(0, 0)
	_day_button.add_item("Giorno corrente")
	_day_button.set_item_metadata(1, -1)
	_day_button.item_selected.connect(_on_day_selected)
	filter_row.add_child(_day_button)
	filter_row.add_child(Control.new()) # spacer
	# Chronicle scroll.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_entries_container = VBoxContainer.new()
	_entries_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_container.add_theme_constant_override("separation", 3)
	scroll.add_child(_entries_container)
	_message_label = Label.new()
	_message_label.add_theme_font_size_override("font_size", 12)
	_message_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65, 0.9))
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_message_label)
	# Button row.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)
	_save_button = Button.new()
	_save_button.text = "Salva adesso"
	_save_button.pressed.connect(_on_save_pressed)
	btn_row.add_child(_save_button)
	_load_button = Button.new()
	_load_button.text = "Carica salvataggio"
	_load_button.pressed.connect(_on_load_pressed)
	btn_row.add_child(_load_button)
	_new_button = Button.new()
	_new_button.text = "Nuovo mondo"
	_new_button.pressed.connect(_on_new_pressed)
	btn_row.add_child(_new_button)
	var close_button := Button.new()
	close_button.text = "Chiudi"
	close_button.pressed.connect(_hide_panel)
	btn_row.add_child(close_button)
	# Confirmation dialog (shared for destructive actions).
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Conferma"
	_confirm_dialog.dialog_text = "Sei sicuro?"
	_confirm_dialog.confirmed.connect(_on_confirm)
	_root.add_child(_confirm_dialog)
	_root.visible = false
	# Register the open_menu action if missing from project.godot — safe no-op
	# if already present.
	_ensure_action_exists("open_menu", [KEY_C])


func _refresh() -> void:
	if _save_status_label == null:
		return
	var info := Game.get_last_save_info()
	var parts: PackedStringArray = []
	if bool(info.get("exists", false)):
		parts.append("Ultimo salvataggio: %s" % String(info.get("real_time_text", "sconosciuto")))
		var sd := int(info.get("sim_day", 0))
		var st := String(info.get("sim_time_text", "--:--"))
		if sd > 0:
			parts.append("mondo al giorno %d, %s" % [sd, st])
		var pop := int(info.get("population", 0))
		if pop > 0:
			parts.append("%d abitanti" % pop)
	else:
		parts.append("Nessun salvataggio presente.")
	var book := Game.get_chronicle_book()
	var count := book.count() if book != null else 0
	parts.append("%d voci di cronaca." % count)
	_save_status_label.text = " · ".join(parts)
	# Load button only enabled when a save exists.
	if _load_button != null:
		_load_button.disabled = not bool(info.get("exists", false))
	_refresh_entries()
	_message_label.text = ""


func _refresh_entries() -> void:
	if _entries_container == null:
		return
	for child in _entries_container.get_children():
		child.queue_free()
	var book := Game.get_chronicle_book()
	if book == null:
		return
	var day_filter := _day_filter
	if day_filter == -1:
		day_filter = Game.get_day()
	var entries := book.query(8, day_filter, _category_filter, ENTRIES_PER_PAGE)
	# Newest first is the order returned by query(); we reverse to show
	# oldest on top for narrative reading.
	entries.reverse()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "Nessun evento da mostrare con questi filtri."
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55, 0.8))
		_entries_container.add_child(empty)
		return
	for e in entries:
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 12)
		var color := _color_for_category(e.category)
		line.add_theme_color_override("font_color", color)
		var time_str := SimulationClock.format_minutes(e.minute_of_day)
		line.text = "Giorno %d, %s · [%s] %s" % [e.day, time_str, e.category_label(), e.summary]
		_entries_container.add_child(line)


func _color_for_category(cat: int) -> Color:
	match cat:
		ChronicleEntry.Category.PRODUCTION:
			return Color(0.58, 0.78, 0.45, 1.0)
		ChronicleEntry.Category.SHORTAGE:
			return Color(0.85, 0.52, 0.40, 1.0)
		ChronicleEntry.Category.HELP:
			return Color(0.55, 0.70, 0.88, 1.0)
		ChronicleEntry.Category.RELATIONSHIP:
			return Color(0.77, 0.65, 0.82, 1.0)
		ChronicleEntry.Category.PROJECT:
			return Color(0.90, 0.78, 0.42, 1.0)
		ChronicleEntry.Category.MILESTONE:
			return Color(0.80, 0.76, 0.62, 1.0)
		ChronicleEntry.Category.SYSTEM:
			return Color(0.55, 0.55, 0.58, 1.0)
	return Color(0.85, 0.82, 0.72, 1.0)


func _on_category_selected(index: int) -> void:
	# The OptionButton holds the category id as the item metadata. The "Tutte"
	# item has metadata -1 which maps to "no filter".
	_category_filter = _category_button.get_item_metadata(index)
	_refresh_entries()


func _on_day_selected(index: int) -> void:
	_day_filter = _day_button.get_item_metadata(index)
	_refresh_entries()


func _on_save_pressed() -> void:
	var info := Game.get_last_save_info()
	if bool(info.get("exists", false)):
		_confirm_save = true
		_confirm_dialog.dialog_text = (
			"Un salvataggio esiste già al giorno %d (%s). Sovrascriverlo?\n\n"
			% [int(info.get("sim_day", 0)), String(info.get("real_time_text", ""))]
		)
		_confirm_dialog.popup_centered()
		return
	_do_save()


func _do_save() -> void:
	var err := Game.request_save()
	if err == SaveManager.Error.OK:
		_message_label.text = "Partita salvata."
		_message_label.add_theme_color_override("font_color", Color(0.55, 0.80, 0.50, 1.0))
	else:
		_message_label.text = "Salvataggio fallito: %s." % SaveManager.error_label(err)
		_message_label.add_theme_color_override("font_color", Color(0.85, 0.50, 0.40, 1.0))
	_refresh()


func _on_load_pressed() -> void:
	_confirm_save = false
	_confirm_dialog.dialog_text = (
		"Caricare l'ultimo salvataggio? I progressi non salvati andranno persi.\n"
		"Il mondo verrà ricaricato dal menu principale (questa versione non ricarica la scena senza riavvio)."
	)
	_confirm_dialog.popup_centered()


func _on_new_pressed() -> void:
	_confirm_save = false
	_confirm_dialog.dialog_text = (
		"Eliminare il salvataggio e cominciare un nuovo mondo?\n"
		"Dovrai riavviare la partita per vedere il nuovo villaggio."
	)
	_confirm_dialog.popup_centered()


func _on_confirm() -> void:
	if _confirm_save:
		_do_save()
		return
	# Load / New do a best-effort scene reload. Godot does not hot-replace
	# the running scene cleanly for all nodes; we document that a restart
	# is required after load/new in v1 (see README).
	# For "New world" we delete the save first.
	if _confirm_dialog.dialog_text.begins_with("Eliminare"):
		_delete_save_files()
		_message_label.text = "Salvataggio eliminato. Riavvia per iniziare un nuovo mondo."
	else:
		# Attempt a live load: re-run the world systems' load path. Because
		# MainWorld has already built the terrain and places we cannot
		# re-instantiate everything here, so we do the state restore via
		# SaveManager and refresh views.
		var sm := Game.get_save_manager()
		if sm != null:
			var res: Array = sm.load_from_file()
			var code: int = res[0]
			if code == SaveManager.Error.OK:
				_message_label.text = String(res[1])
				_message_label.add_theme_color_override("font_color", Color(0.55, 0.80, 0.50, 1.0))
			else:
				_message_label.text = "Caricamento fallito: %s — %s" % [
					SaveManager.error_label(code), String(res[1])
				]
				_message_label.add_theme_color_override(
					"font_color", Color(0.85, 0.50, 0.40, 1.0)
				)
	_refresh()


func _delete_save_files() -> void:
	var sm := Game.get_save_manager()
	if sm == null:
		return
	var paths := [sm.save_path(), sm.backup_path(), sm.tmp_path()]
	for p in paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	sm.last_save_real_time = 0
	sm.last_save_simulated_day = 0
	sm.last_save_simulated_time_text = ""
	sm.last_save_population = 0


func _on_save_performed() -> void:
	if _visible:
		_refresh()


func _on_background_input(event: InputEvent) -> void:
	# Click outside the panel closes it, like a modal dialog.
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_panel()


func _ensure_action_exists(action_name: String, keys: Array) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action_name, ev)
