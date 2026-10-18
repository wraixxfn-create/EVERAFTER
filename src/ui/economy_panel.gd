class_name EconomyPanel
extends CanvasLayer
## Read-only observation panel for the local village economy.
##
## Like `NpcPanel`, this panel owns zero simulation state and maintains no
## independent counters: every label is formatted directly from the live
## `EconomySystem` registered with `Game` (or injected by a test via
## [method bind_system]).

const MAX_DISPLAYED_TRANSACTIONS := 5

var _system: EconomySystem = null

@onready var _root: Control = $Root
@onready var _header_label: Label = $Root/Panel/Margin/Lines/HeaderLabel
@onready var _food_amount_label: Label = $Root/Panel/Margin/Lines/ResourceGrid/FoodAmount
@onready var _food_flow_label: Label = $Root/Panel/Margin/Lines/ResourceGrid/FoodFlow
@onready var _wood_amount_label: Label = $Root/Panel/Margin/Lines/ResourceGrid/WoodAmount
@onready var _wood_flow_label: Label = $Root/Panel/Margin/Lines/ResourceGrid/WoodFlow
@onready var _stone_amount_label: Label = $Root/Panel/Margin/Lines/ResourceGrid/StoneAmount
@onready var _stone_flow_label: Label = $Root/Panel/Margin/Lines/ResourceGrid/StoneFlow
@onready var _coin_amount_label: Label = $Root/Panel/Margin/Lines/ResourceGrid/CoinAmount
@onready var _coin_flow_label: Label = $Root/Panel/Margin/Lines/ResourceGrid/CoinFlow
@onready var _projects_label: Label = $Root/Panel/Margin/Lines/ProjectsLabel
@onready var _shortages_label: Label = $Root/Panel/Margin/Lines/ShortagesLabel
@onready var _transactions_title: Label = $Root/Panel/Margin/Lines/TransactionsTitle
@onready var _transactions_label: Label = $Root/Panel/Margin/Lines/TransactionsLabel


func _ready() -> void:
	_root.theme = UiTheme.shared_theme()
	UiTheme.style_title_label(_header_label, 15)
	UiTheme.style_section_label(_transactions_title, 12)
	EventBus.economy_system_ready.connect(_on_economy_system_ready)
	_refresh_system()
	refresh_view()


func _process(_delta: float) -> void:
	if _system == null and Game.get_economy_system() != null:
		_refresh_system()
	refresh_view()


## Allows tests (or a custom composition root) to bind an `EconomySystem`
## explicitly and refresh the UI immediately.
func bind_system(system: EconomySystem) -> void:
	_system = system
	refresh_view()


## Reads every displayed value from `_system` and updates the labels.
func refresh_view() -> void:
	if _system == null:
		_show_empty()
		return
	_header_label.text = "ECONOMIA DEL VILLAGGIO"
	_update_resource_row(ResourceType.FOOD, _food_amount_label, _food_flow_label)
	_update_resource_row(ResourceType.WOOD, _wood_amount_label, _wood_flow_label)
	_update_resource_row(ResourceType.STONE, _stone_amount_label, _stone_flow_label)
	var coin_amount := _system.get_village_resource(ResourceType.COIN)
	_coin_amount_label.text = "%d" % coin_amount
	_coin_amount_label.add_theme_color_override(
		"font_color", _color_for_stock(ResourceType.COIN, coin_amount, UiTheme.TEXT_GOLD)
	)
	_coin_flow_label.text = (
		"Mercato: %d" % _system.market_inventory.get_amount(ResourceType.COIN)
	)
	_projects_label.text = EconomyRules.format_projects(_system)
	var shortage_summary := EconomyRules.format_shortages(_system)
	_shortages_label.text = "Carenze: %s" % shortage_summary
	if shortage_summary == "Nessuna carenza attiva":
		_shortages_label.add_theme_color_override("font_color", UiTheme.TEXT_GOOD)
	elif shortage_summary.contains("esaurite") or shortage_summary.contains("critica"):
		_shortages_label.add_theme_color_override("font_color", UiTheme.TEXT_CRITICAL)
	else:
		_shortages_label.add_theme_color_override("font_color", UiTheme.TEXT_WARN)
	_transactions_label.text = _format_recent_transactions()


func get_displayed_amount_text(resource_id: String) -> String:
	var result := ""
	match resource_id:
		ResourceType.FOOD:
			result = _food_amount_label.text
		ResourceType.WOOD:
			result = _wood_amount_label.text
		ResourceType.STONE:
			result = _stone_amount_label.text
		ResourceType.COIN:
			result = _coin_amount_label.text
	return result


func get_displayed_amount(resource_id: String) -> int:
	return int(get_displayed_amount_text(resource_id))


func get_displayed_flow_text(resource_id: String) -> String:
	var result := ""
	match resource_id:
		ResourceType.FOOD:
			result = _food_flow_label.text
		ResourceType.WOOD:
			result = _wood_flow_label.text
		ResourceType.STONE:
			result = _stone_flow_label.text
		ResourceType.COIN:
			result = _coin_flow_label.text
	return result


func get_displayed_shortages() -> String:
	return _shortages_label.text


func get_displayed_projects() -> String:
	return _projects_label.text


func get_displayed_transactions() -> String:
	return _transactions_label.text


# --- internals ---------------------------------------------------------------


func _refresh_system() -> void:
	_system = Game.get_economy_system()


func _on_economy_system_ready() -> void:
	_refresh_system()
	refresh_view()


func _update_resource_row(
	resource_id: String, amount_label: Label, flow_label: Label
) -> void:
	var amount := _system.get_village_resource(resource_id)
	amount_label.text = "%d" % amount
	amount_label.add_theme_color_override(
		"font_color", _color_for_stock(resource_id, amount, UiTheme.TEXT_PARCHMENT)
	)
	var produced := _system.get_production(resource_id, true)
	var consumed := _system.get_consumption(resource_id, true)
	flow_label.text = "+%d / -%d" % [produced, consumed]
	if produced > consumed:
		flow_label.add_theme_color_override("font_color", UiTheme.TEXT_GOOD)
	elif consumed > produced:
		flow_label.add_theme_color_override("font_color", UiTheme.TEXT_WARN)
	else:
		flow_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)


static func _color_for_stock(
	resource_id: String, amount: int, normal_color: Color
) -> Color:
	if amount <= 0:
		return UiTheme.TEXT_CRITICAL
	if amount < ResourceType.shortage_threshold(resource_id):
		return UiTheme.TEXT_WARN
	return normal_color


func _format_recent_transactions() -> String:
	var recent := EconomyRules.recent_transactions(
		_system, MAX_DISPLAYED_TRANSACTIONS, true
	)
	if recent.is_empty():
		return "Nessuna transazione registrata."
	var lines: PackedStringArray = []
	for tx in recent:
		lines.append(tx.format_short())
	return "\n".join(lines)


func _show_empty() -> void:
	_header_label.text = "ECONOMIA DEL VILLAGGIO"
	_food_amount_label.text = "—"
	_food_flow_label.text = "—"
	_wood_amount_label.text = "—"
	_wood_flow_label.text = "—"
	_stone_amount_label.text = "—"
	_stone_flow_label.text = "—"
	_coin_amount_label.text = "—"
	_coin_flow_label.text = "—"
	_projects_label.text = "Progetti: —"
	_shortages_label.text = "Carenze: —"
	_transactions_label.text = "In attesa del sistema economico…"
