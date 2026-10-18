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
## Styled with [UiTheme] to match the medieval village aesthetic. The panel
## never drives the simulation; it only calls `Game.request_save()` and reads
## state from `Game` / `ChronicleBook`.

const PANEL_WIDTH := 560
const PANEL_HEIGHT := 640
const ENTRIES_PER_PAGE := 200

const CATEGORY_COLORS := {
	ChronicleEntry.Category.PRODUCTION: Color(0.62, 0.82, 0.48, 1.0),
	ChronicleEntry.Category.SHORTAGE: Color(0.90, 0.52, 0.40, 1.0),
	ChronicleEntry.Category.HELP: Color(0.58, 0.74, 0.90, 1.0),
	ChronicleEntry.Category.RELATIONSHIP: Color(0.80, 0.68, 0.86, 1.0),
	ChronicleEntry.Category.PROJECT: Color(0.94, 0.80, 0.44, 1.0),
	ChronicleEntry.Category.MILESTONE: Color(0.92, 0.86, 0.66, 1.0),
	ChronicleEntry.Category.SYSTEM: Color(0.70, 0.68, 0.64, 1.0),
}

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


func is_panel_open() -> bool:
	return _visible


func _show_panel() -> void:
	_visible = true
	_root.visible = true
	# Clear stale feedback only when the panel opens: `_refresh()` also runs
	# right after Save/Load/New and must not wipe their result message.
	_message_label.text = ""
	_refresh()
	# Release mouse so the panel is clickable.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _hide_panel() -> void:
	_visible = false
	_root.visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UiTheme.shared_theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.02, 0.02, 0.62)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_background_input)
	_root.add_child(bg)
	add_child(_root)

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
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.make_panel_style(
			UiTheme.BG_MODAL, UiTheme.BORDER_GOLD_BRIGHT, 8, 18.0, 16.0
		)
	)
	_root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	_build_header_section(vbox)
	_build_filter_row(vbox)
	_build_chronicle_area(vbox)
	_build_footer_buttons(vbox)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Conferma operazione"
	_confirm_dialog.dialog_text = "Sei sicuro?"
	_confirm_dialog.confirmed.connect(_on_confirm)
	_root.add_child(_confirm_dialog)
	_root.visible = false
	_ensure_action_exists("open_menu", [KEY_C])


func _build_header_section(vbox: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "CRONACHE DEL VILLAGGIO E SALVATAGGIO"
	UiTheme.style_title_label(title, 17)
	vbox.add_child(title)

	_save_status_label = Label.new()
	_save_status_label.add_theme_font_size_override("font_size", 12)
	_save_status_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	_save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_save_status_label)
	vbox.add_child(HSeparator.new())


func _build_filter_row(vbox: VBoxContainer) -> void:
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 10)
	vbox.add_child(filter_row)
	var cat_label := Label.new()
	cat_label.text = "Categoria:"
	cat_label.add_theme_font_size_override("font_size", 12)
	cat_label.add_theme_color_override("font_color", UiTheme.TEXT_GOLD)
	filter_row.add_child(cat_label)

	_category_button = OptionButton.new()
	_category_button.tooltip_text = "Filtra le voci della cronaca per argomento."
	_category_button.add_item("Tutte le voci")
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
	day_label.text = "Periodo:"
	day_label.add_theme_font_size_override("font_size", 12)
	day_label.add_theme_color_override("font_color", UiTheme.TEXT_GOLD)
	filter_row.add_child(day_label)

	_day_button = OptionButton.new()
	_day_button.tooltip_text = "Mostra l'intera cronaca oppure soltanto il giorno in corso."
	_day_button.add_item("Tutti i giorni")
	_day_button.set_item_metadata(0, 0)
	_day_button.add_item("Giorno corrente")
	_day_button.set_item_metadata(1, -1)
	_day_button.item_selected.connect(_on_day_selected)
	filter_row.add_child(_day_button)


func _build_chronicle_area(vbox: VBoxContainer) -> void:
	var ledger_box := PanelContainer.new()
	ledger_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ledger_box.add_theme_stylebox_override(
		"panel", UiTheme.make_inset_style(UiTheme.BG_INSET, UiTheme.BORDER_SUBTLE, 6, 10.0, 8.0)
	)
	vbox.add_child(ledger_box)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ledger_box.add_child(scroll)

	_entries_container = VBoxContainer.new()
	_entries_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_container.add_theme_constant_override("separation", 5)
	scroll.add_child(_entries_container)

	_message_label = Label.new()
	_message_label.add_theme_font_size_override("font_size", 13)
	_message_label.add_theme_color_override("font_color", UiTheme.TEXT_GOLD)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_message_label)


func _build_footer_buttons(vbox: VBoxContainer) -> void:
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)
	_save_button = Button.new()
	_save_button.text = "Salva adesso"
	_save_button.tooltip_text = "Salva subito lo stato del villaggio, degli abitanti e della cronaca."
	_save_button.pressed.connect(_on_save_pressed)
	btn_row.add_child(_save_button)
	_load_button = Button.new()
	_load_button.text = "Carica salvataggio"
	_load_button.tooltip_text = "Ripristina l'ultimo salvataggio disponibile su disco."
	_load_button.pressed.connect(_on_load_pressed)
	btn_row.add_child(_load_button)
	_new_button = Button.new()
	_new_button.text = "Nuovo mondo"
	_new_button.tooltip_text = "Elimina il file di salvataggio per ricominciare da zero al riavvio."
	_new_button.pressed.connect(_on_new_pressed)
	btn_row.add_child(_new_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "Chiudi (Esc)"
	close_button.tooltip_text = "Chiude il pannello e torna al villaggio."
	close_button.pressed.connect(_hide_panel)
	btn_row.add_child(close_button)


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
	if _load_button != null:
		_load_button.disabled = not bool(info.get("exists", false))
	_refresh_entries()


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
	entries.reverse()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "Nessun evento registrato per i filtri selezionati."
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
		_entries_container.add_child(empty)
		return
	for e in entries:
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 12)
		var color := _color_for_category(e.category)
		line.add_theme_color_override("font_color", color)
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color(0.15, 0.12, 0.095, 0.55)
		row_style.border_width_left = 3
		row_style.border_color = color
		row_style.corner_radius_top_right = 4
		row_style.corner_radius_bottom_right = 4
		row_style.content_margin_left = 8.0
		row_style.content_margin_right = 6.0
		row_style.content_margin_top = 4.0
		row_style.content_margin_bottom = 4.0
		line.add_theme_stylebox_override("normal", row_style)
		var time_str := SimulationClock.format_minutes(e.minute_of_day)
		line.text = "Giorno %d, %s · [%s] %s" % [
			e.day, time_str, e.category_label(), e.summary
		]
		_entries_container.add_child(line)


func _color_for_category(cat: int) -> Color:
	return CATEGORY_COLORS.get(cat, Color(0.85, 0.82, 0.72, 1.0))


func _on_category_selected(index: int) -> void:
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
		_message_label.text = "✓ Partita salvata con successo."
		_message_label.add_theme_color_override("font_color", UiTheme.TEXT_GOOD)
	else:
		_message_label.text = "Salvataggio fallito: %s." % SaveManager.error_label(err)
		_message_label.add_theme_color_override("font_color", UiTheme.TEXT_CRITICAL)
	_refresh()


func _on_load_pressed() -> void:
	_confirm_save = false
	_confirm_dialog.dialog_text = (
		"Caricare l'ultimo salvataggio? I progressi non salvati andranno persi.\n"
		+ "Lo stato dei sistemi verrà ripristinato dal file di salvataggio."
	)
	_confirm_dialog.popup_centered()


func _on_new_pressed() -> void:
	_confirm_save = false
	_confirm_dialog.dialog_text = (
		"Eliminare il salvataggio e cominciare un nuovo mondo?\n"
		+ "Dovrai riavviare la partita per vedere il nuovo villaggio."
	)
	_confirm_dialog.popup_centered()


func _on_confirm() -> void:
	if _confirm_save:
		_do_save()
		return
	if _confirm_dialog.dialog_text.begins_with("Eliminare"):
		_delete_save_files()
		_message_label.text = "Salvataggio eliminato. Riavvia per iniziare un nuovo mondo."
		_message_label.add_theme_color_override("font_color", UiTheme.TEXT_WARN)
	else:
		var sm := Game.get_save_manager()
		if sm != null:
			var res: Array = sm.load_from_file()
			var code: int = res[0]
			if code == SaveManager.Error.OK:
				_message_label.text = String(res[1])
				_message_label.add_theme_color_override("font_color", UiTheme.TEXT_GOOD)
			else:
				_message_label.text = "Caricamento fallito: %s — %s" % [
					SaveManager.error_label(code), String(res[1])
				]
				_message_label.add_theme_color_override(
					"font_color", UiTheme.TEXT_CRITICAL
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
