class_name NpcPanel
extends CanvasLayer
## Observation panel for the inhabitants.
##
## It does not own any simulation state. It asks `Game.get_npc_system()` for the
## current records and listens to `EventBus.npc_selected`, so the list and a
## click in the 3D world select the same character. When an NPC is far away and
## has no 3D view, the panel keeps showing live data: this is the visible proof
## that simulation and representation are separate.
##
## The panel is deliberately plain: name, profession, activity, goal, three
## need bars, a short state summary and — since the social phase — the few
## relationships and memories that explain why this character behaves like this.
## No debug numbers, no hidden actions: the social section shows three
## relationships and three memories, in words, and names the event behind the
## last documented change instead of listing every value it owns.

const PLACEHOLDER_ID := ""
const RELATION_LINES := 3
const MEMORY_LINES := 3

var _system: NpcSimulationSystem = null
var _social: SocialSystem = null
var _selected_id: String = ""

@onready var _header_label: Label = $Root/Panel/Margin/Lines/HeaderLabel
@onready var _selector: OptionButton = $Root/Panel/Margin/Lines/Selector
@onready var _name_label: Label = $Root/Panel/Margin/Lines/NameLabel
@onready var _profession_label: Label = $Root/Panel/Margin/Lines/ProfessionLabel
@onready var _activity_label: Label = $Root/Panel/Margin/Lines/ActivityLabel
@onready var _goal_label: Label = $Root/Panel/Margin/Lines/GoalLabel
@onready var _energy_bar: ProgressBar = $Root/Panel/Margin/Lines/NeedsGrid/EnergyBar
@onready var _energy_value: Label = $Root/Panel/Margin/Lines/NeedsGrid/EnergyValue
@onready var _hunger_bar: ProgressBar = $Root/Panel/Margin/Lines/NeedsGrid/HungerBar
@onready var _hunger_value: Label = $Root/Panel/Margin/Lines/NeedsGrid/HungerValue
@onready var _wellbeing_bar: ProgressBar = $Root/Panel/Margin/Lines/NeedsGrid/WellbeingBar
@onready var _wellbeing_value: Label = $Root/Panel/Margin/Lines/NeedsGrid/WellbeingValue
@onready var _summary_label: Label = $Root/Panel/Margin/Lines/SummaryLabel
@onready var _relations_label: Label = $Root/Panel/Margin/Lines/RelationsLabel
@onready var _memories_label: Label = $Root/Panel/Margin/Lines/MemoriesLabel


func _ready() -> void:
	EventBus.npc_system_ready.connect(_on_system_ready)
	EventBus.social_system_ready.connect(_on_system_ready)
	EventBus.npc_selected.connect(_on_npc_selected)
	_selector.item_selected.connect(_on_selector_item_selected)
	_refresh_system()
	_refresh_detail()


func _process(_delta: float) -> void:
	if _system != Game.get_npc_system():
		_refresh_system()
	_social = Game.get_social_system()
	_refresh_detail()


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


# --- internals ---------------------------------------------------------------


func _refresh_system() -> void:
	_system = Game.get_npc_system()
	_selector.clear()
	_selector.add_item("Scegli un abitante…", 0)
	_selector.set_item_metadata(0, PLACEHOLDER_ID)
	_selector.set_item_disabled(0, true)
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
	_name_label.text = record.display_name
	_profession_label.text = "%s · %d anni" % [record.profession_label, record.age]
	_activity_label.text = "Attività: %s" % record.activity_label()
	_goal_label.text = "Obiettivo: %s" % record.goal_label()
	_energy_bar.value = record.needs.energy
	_hunger_bar.value = record.needs.hunger
	_wellbeing_bar.value = record.needs.wellbeing
	_energy_value.text = "%d" % int(round(record.needs.energy))
	_hunger_value.text = "%d" % int(round(record.needs.hunger))
	_wellbeing_value.text = "%d" % int(round(record.needs.wellbeing))
	_summary_label.text = record.summary_text()
	_relations_label.text = _relations_text(record.id)
	_memories_label.text = _memories_text(record.id)


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
	_name_label.text = title
	_profession_label.text = "—"
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


func _on_selector_item_selected(index: int) -> void:
	var npc_id := String(_selector.get_item_metadata(index))
	select_npc(npc_id)


func _on_npc_selected(npc_id: String) -> void:
	_selected_id = npc_id
	if _system != null and not npc_id.is_empty() and _system.get_record(npc_id) == null:
		_selected_id = ""
	_select_in_option_button(_selected_id)
	_refresh_detail()


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
