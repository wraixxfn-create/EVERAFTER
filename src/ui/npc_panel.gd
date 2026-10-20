class_name NpcPanel
extends CanvasLayer
## Observation panel for the inhabitants.
##
## A single right-hand column: header, selector, identity, vitals, and a
## scrollable dossier (traits, goal, current state, bonds, memories). It owns no
## simulation state — it asks `Game.get_npc_system()` for the current records and
## listens to `EventBus.npc_selected`, so the list and a click in the 3D world
## select the same character. When an NPC is far away and has no 3D view, the
## panel keeps showing live data: the visible proof that simulation and
## representation are separate.
##
## With nothing selected the dossier collapses to two lines, so the card never
## covers the village for no reason.

const PLACEHOLDER_ID := ""
const RELATION_LINES := 3
const MEMORY_LINES := 3

var _system: NpcSimulationSystem = null
var _social: SocialSystem = null
var _selected_id := ""
var _last_needs_key := Vector3i(-1, -1, -1)
var _last_body_height := -1.0

@onready var _root: Control = $Root
@onready var _panel: PanelContainer = $Root/Panel
@onready var _header_label: Label = $Root/Panel/Margin/Lines/HeaderLabel
@onready var _selector: OptionButton = $Root/Panel/Margin/Lines/Selector
@onready var _name_label: Label = $Root/Panel/Margin/Lines/NameLabel
@onready var _profession_label: Label = $Root/Panel/Margin/Lines/ProfessionLabel
@onready var _activity_label: Label = $Root/Panel/Margin/Lines/ActivityLabel
@onready var _goal_label: Label = $Root/Panel/Margin/Lines/BodyScroll/Body/GoalLabel
@onready var _traits_label: Label = $Root/Panel/Margin/Lines/BodyScroll/Body/TraitsLabel
@onready var _needs_title: Label = $Root/Panel/Margin/Lines/NeedsTitle
@onready var _needs_grid: GridContainer = $Root/Panel/Margin/Lines/NeedsGrid
@onready var _energy_bar: ProgressBar = $Root/Panel/Margin/Lines/NeedsGrid/EnergyBar
@onready var _energy_value: Label = $Root/Panel/Margin/Lines/NeedsGrid/EnergyValue
@onready var _hunger_bar: ProgressBar = $Root/Panel/Margin/Lines/NeedsGrid/HungerBar
@onready var _hunger_value: Label = $Root/Panel/Margin/Lines/NeedsGrid/HungerValue
@onready var _wellbeing_bar: ProgressBar = $Root/Panel/Margin/Lines/NeedsGrid/WellbeingBar
@onready var _wellbeing_value: Label = $Root/Panel/Margin/Lines/NeedsGrid/WellbeingValue
@onready var _body_scroll: ScrollContainer = $Root/Panel/Margin/Lines/BodyScroll
@onready var _body: VBoxContainer = $Root/Panel/Margin/Lines/BodyScroll/Body
@onready var _summary_title: Label = $Root/Panel/Margin/Lines/BodyScroll/Body/SummaryTitle
@onready var _summary_label: Label = $Root/Panel/Margin/Lines/BodyScroll/Body/SummaryLabel
@onready var _relations_title: Label = $Root/Panel/Margin/Lines/BodyScroll/Body/RelationsTitle
@onready var _relations_label: Label = $Root/Panel/Margin/Lines/BodyScroll/Body/RelationsLabel
@onready var _memories_title: Label = $Root/Panel/Margin/Lines/BodyScroll/Body/MemoriesTitle
@onready var _memories_label: Label = $Root/Panel/Margin/Lines/BodyScroll/Body/MemoriesLabel
@onready var _hint_label: Label = $Root/Panel/Margin/Lines/HintLabel
@onready var _needs_labels: Array[Label] = [
	$Root/Panel/Margin/Lines/NeedsGrid/EnergyLabel,
	$Root/Panel/Margin/Lines/NeedsGrid/HungerLabel,
	$Root/Panel/Margin/Lines/NeedsGrid/WellbeingLabel,
]


func _ready() -> void:
	_root.theme = UiTheme.shared_theme()
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.make_panel_style(UiTheme.BG_HUD, UiTheme.BORDER_BRASS, UiTheme.PANEL_RADIUS, 18.0, 16.0)
	)
	UiTheme.style_section_label(_header_label, 10)
	UiTheme.style_title_label(_name_label, 19, UiTheme.TEXT_PARCHMENT)
	UiTheme.style_body_label(_profession_label, 11, UiTheme.TEXT_MUTED)
	UiTheme.style_neutral_chip(_activity_label)
	for title in [_needs_title, _summary_title, _relations_title, _memories_title]:
		UiTheme.style_section_label(title, 10)
	for need in _needs_labels:
		UiTheme.style_body_label(need, 11, UiTheme.TEXT_MUTED)
	for value in [_energy_value, _hunger_value, _wellbeing_value]:
		UiTheme.style_body_label(value, 11, UiTheme.TEXT_SECONDARY)
	UiTheme.style_body_label(_traits_label, 11, UiTheme.TEXT_MUTED)
	UiTheme.style_body_label(_goal_label, 12, UiTheme.TEXT_SECONDARY)
	UiTheme.style_body_label(_summary_label, 12, UiTheme.TEXT_SECONDARY)
	UiTheme.style_body_label(_relations_label, 12, UiTheme.TEXT_SECONDARY)
	UiTheme.style_body_label(_memories_label, 12, UiTheme.TEXT_SECONDARY)
	UiTheme.style_body_label(_hint_label, 10, UiTheme.TEXT_MUTED)
	EventBus.npc_system_ready.connect(_on_system_ready)
	EventBus.social_system_ready.connect(_on_system_ready)
	EventBus.npc_selected.connect(_on_npc_selected)
	_selector.item_selected.connect(_on_selector_item_selected)
	_refresh_system()
	_refresh_detail()
	_fit()
	get_viewport().size_changed.connect(_fit)


func _process(_delta: float) -> void:
	if _system != Game.get_npc_system():
		_refresh_system()
	_social = Game.get_social_system()
	_refresh_detail()
	# Re-measure only when wrapped text actually changed height: a fit on every
	# frame would fight the container layout.
	var body_height := _body.get_combined_minimum_size().y
	if absf(body_height - _last_body_height) > 0.5:
		_last_body_height = body_height
		_fit()


## Public entry point used by the integration test and by the selector.
func select_npc(npc_id: String) -> void:
	EventBus.npc_selected.emit(npc_id)


func get_selected_id() -> String:
	return _selected_id


func get_selector_item_count() -> int:
	return _selector.item_count


## Text actually shown in the panel. Used by the integration test to prove that
## the widgets are wired to the selected record, not just that selection works.
func get_displayed_name() -> String:
	return _name_label.text


func get_displayed_activity() -> String:
	return _activity_label.text


func get_displayed_goal() -> String:
	return _goal_label.text


func get_displayed_summary() -> String:
	return _summary_label.text


func get_displayed_energy() -> float:
	return _energy_bar.value


## Text of the social section, exactly as shown. The integration test reads it
## to prove the panel is wired to the social layer and not to a private copy.
func get_displayed_relations() -> String:
	return _relations_label.text


func get_displayed_memories() -> String:
	return _memories_label.text


# --- layout ------------------------------------------------------------------


## Sizes the card from the header, the (bounded) dossier and the hint line.
func _fit() -> void:
	if not is_inside_tree():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var available := maxf(viewport_size.y - 2.0 * UiTheme.SCREEN_MARGIN, 160.0)
	var max_scroll := maxf(available * 0.46, 120.0)
	if _body_scroll.visible:
		var body_height := _body.get_combined_minimum_size().y
		_body_scroll.custom_minimum_size.y = minf(body_height, max_scroll)
	else:
		_body_scroll.custom_minimum_size.y = 0.0
	var wanted := _panel.get_combined_minimum_size().y
	_panel.offset_left = -UiTheme.SCREEN_MARGIN - UiTheme.RIGHT_COLUMN_WIDTH
	_panel.offset_top = UiTheme.SCREEN_MARGIN
	_panel.offset_right = -UiTheme.SCREEN_MARGIN
	_panel.offset_bottom = _panel.offset_top + minf(wanted, available)


# --- internals ---------------------------------------------------------------


func _refresh_system() -> void:
	_system = Game.get_npc_system()
	_selector.clear()
	_selector.add_item("Scegli un abitante…", 0)
	_selector.set_item_metadata(0, PLACEHOLDER_ID)
	if _system == null:
		_header_label.text = "ABITANTI"
		_selector.select(0)
		return
	var records := _system.get_records()
	_header_label.text = "ABITANTI · %d" % records.size()
	for index in records.size():
		var record := records[index]
		_selector.add_item(
			"%s — %s" % [record.display_name, record.profession_label], index + 1
		)
		_selector.set_item_metadata(index + 1, record.id)
	if _selected_id.is_empty():
		_selector.select(0)
	else:
		_select_in_option_button(_selected_id)


func _refresh_detail() -> void:
	if _system == null:
		_show_empty("Nessun abitante selezionato", "Avvia il mondo per osservare gli abitanti.")
		return
	var record := _system.get_record(_selected_id)
	if record == null:
		_show_empty(
			"Nessun abitante selezionato",
			"Scegli un nome dall'elenco o clicca un abitante nel villaggio."
		)
		return
	_set_detail_sections_visible(true)
	_name_label.text = record.display_name
	var shift_text := "%s–%s" % [
		SimulationClock.format_minutes(record.work_start_minute),
		SimulationClock.format_minutes(record.work_end_minute),
	]
	_profession_label.text = "%s · %d anni · Umore %s · Turno %s" % [
		record.profession_label,
		record.age,
		record.mood_label(),
		shift_text,
	]
	_profession_label.add_theme_color_override(
		"font_color", record.profession_color.lightened(0.45)
	)
	var p := record.personality
	_traits_label.text = (
		"Indole: Diligenza %d · Socievolezza %d · Curiosità %d · Calma %d"
		% [p.diligence, p.sociability, p.curiosity, p.calmness]
	)
	_activity_label.text = "Attività: %s" % record.activity_label()
	_activity_label.add_theme_color_override(
		"font_color", UiTheme.color_for_activity(record.activity)
	)
	_goal_label.text = "Obiettivo: %s" % record.goal_label()
	_update_needs_bars(record)
	_summary_label.text = record.summary_text()
	_relations_label.text = _relations_text(record.id)
	_memories_label.text = _memories_text(record.id)


func _update_needs_bars(record: NpcRecord) -> void:
	var energy := record.needs.energy
	var hunger := record.needs.hunger
	var wellbeing := record.needs.wellbeing
	var key := Vector3i(int(round(energy)), int(round(hunger)), int(round(wellbeing)))
	if key == _last_needs_key:
		return
	_last_needs_key = key
	_energy_bar.value = energy
	_hunger_bar.value = hunger
	_wellbeing_bar.value = wellbeing
	_energy_value.text = "%d" % key.x
	_hunger_value.text = "%d" % key.y
	_wellbeing_value.text = "%d" % key.z
	_energy_bar.add_theme_stylebox_override(
		"fill", UiTheme.make_bar_fill_style(UiTheme.color_for_energy(energy))
	)
	_hunger_bar.add_theme_stylebox_override(
		"fill", UiTheme.make_bar_fill_style(UiTheme.color_for_hunger(hunger))
	)
	_wellbeing_bar.add_theme_stylebox_override(
		"fill", UiTheme.make_bar_fill_style(UiTheme.color_for_wellbeing(wellbeing))
	)


## Up to three relationships, strongest first, plus the documented reason of the
## last change when the social layer has one to show.
func _relations_text(npc_id: String) -> String:
	if _social == null:
		return "Nessuna relazione conosciuta."
	var lines := _social.relationship_lines(npc_id, RELATION_LINES)
	var explanation := _social.change_explanation(npc_id)
	if not explanation.is_empty():
		lines.append("Ultimo cambiamento: %s" % explanation)
	return "\n".join(lines)


func _memories_text(npc_id: String) -> String:
	if _social == null:
		return "Nessun ricordo rilevante."
	return "\n".join(_social.memory_lines(npc_id, MEMORY_LINES))


func _show_empty(title: String, hint: String) -> void:
	_set_detail_sections_visible(false)
	_name_label.text = title
	_profession_label.text = "—"
	_traits_label.text = ""
	_activity_label.text = "Attività: —"
	_goal_label.text = "Obiettivo: —"
	_energy_bar.value = 0.0
	_hunger_bar.value = 0.0
	_wellbeing_bar.value = 0.0
	_energy_value.text = "—"
	_hunger_value.text = "—"
	_wellbeing_value.text = "—"
	_summary_label.text = hint
	_relations_label.text = "Nessuna relazione conosciuta."
	_memories_label.text = "Nessun ricordo rilevante."
	_hint_label.text = "Clic sinistro su un abitante o scegli dall'elenco."
	_last_needs_key = Vector3i(-1, -1, -1)
	_last_body_height = -1.0


func _set_detail_sections_visible(show_details: bool) -> void:
	for control in [
		_profession_label,
		_activity_label,
		_needs_title,
		_needs_grid,
		_body_scroll,
	]:
		if control != null:
			control.visible = show_details


func _on_selector_item_selected(index: int) -> void:
	var npc_id := String(_selector.get_item_metadata(index))
	select_npc(npc_id)


func _on_npc_selected(npc_id: String) -> void:
	_selected_id = npc_id
	if _system != null and not npc_id.is_empty() and _system.get_record(npc_id) == null:
		_selected_id = ""
	_select_in_option_button(_selected_id)
	_refresh_detail()
	_last_body_height = -1.0
	_fit()


func _on_system_ready() -> void:
	_refresh_system()
	_social = Game.get_social_system()
	_refresh_detail()


func _select_in_option_button(npc_id: String) -> void:
	if npc_id.is_empty():
		_selector.select(0)
		return
	for index in _selector.item_count:
		if String(_selector.get_item_metadata(index)) == npc_id:
			_selector.select(index)
			return
	_selector.select(0)
