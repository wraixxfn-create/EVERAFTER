class_name EconomySystem
extends SimulationSystem
## Deterministic local economy system for Everafter.
##
## Connects NPC professions and daily work routines to the collective village
## storehouse (`village`), individual inhabitant satchels (`npc_001`..`npc_016`)
## and the market emporium (`market`).
##
## Core guarantees:
## * pure logic (`RefCounted` via `SimulationSystem`): no nodes, no meshes, no
##   scene tree, runnable headless;
## * non-negative integer resource quantities (`food`, `wood`, `stone`, `coin`);
## * atomic transfers, trades and project payments: a failed transaction never
##   partially mutates any inventory;
## * production requires active `WORKING` ticks at a valid, ready workplace;
## * the merchant facilitates exchanges between existing inventories at
##   documented base prices and never creates resources or coin out of nothing;
## * food scarcity impacts inhabitant needs (`hunger` and `wellbeing`) without
##   introducing mortality or irreversible famine.

const SYSTEM_NAME := "economy"
const TAG := "Economy"

const VILLAGE_OWNER_ID := "village"
const MARKET_OWNER_ID := "market"

const INITIAL_VILLAGE_FOOD := 24
const INITIAL_VILLAGE_WOOD := 12
const INITIAL_VILLAGE_STONE := 10
const INITIAL_VILLAGE_COIN := 60

const INITIAL_MARKET_FOOD := 18
const INITIAL_MARKET_WOOD := 14
const INITIAL_MARKET_STONE := 14
const INITIAL_MARKET_COIN := 50

const INITIAL_NPC_COIN := 4
const MAX_TRANSACTION_HISTORY := 120

const SUPPER_MINUTE_OF_DAY := 19 * 60
const PROJECT_CHECK_MINUTE_OF_DAY := 16 * 60

var village_inventory: ResourceInventory = null
var market_inventory: ResourceInventory = null
var npc_inventories: Dictionary = {}
var completed_projects: PackedStringArray = []
var transactions: Array[EconomyTransaction] = []
var rejected_transaction_count: int = 0
var unfed_meal_attempts_period: int = 0
var unfed_meal_attempts_total: int = 0

var _npc_system: NpcSimulationSystem = null
var _work_progress: Dictionary = {}
var _workplace_prerequisites: Dictionary = {}
var _profession_rules: Dictionary = {}
var _projects: Array[EconomyRules.CommunityProject] = []
var _resource_bonus_per_batch: Dictionary = {}
var _next_transaction_id: int = 1

var _period_production: Dictionary = {}
var _period_consumption: Dictionary = {}
var _previous_period_production: Dictionary = {}
var _previous_period_consumption: Dictionary = {}
var _total_production: Dictionary = {}
var _total_consumption: Dictionary = {}
var _ate_today: Dictionary = {}

var _start_tick: int = 0
var _last_tick: int = -1
var _current_day_index: int = 0
var _initialized: bool = false
var _initial_snapshot: Dictionary = {}


func _init(
	npc_system: NpcSimulationSystem = null,
	initial_village_food: int = INITIAL_VILLAGE_FOOD,
	initial_village_wood: int = INITIAL_VILLAGE_WOOD,
	initial_village_stone: int = INITIAL_VILLAGE_STONE,
	initial_village_coin: int = INITIAL_VILLAGE_COIN
) -> void:
	_npc_system = npc_system
	_profession_rules = EconomyRules.build_profession_rules()
	_workplace_prerequisites = EconomyRules.default_workplace_prerequisites()
	_projects = EconomyRules.build_community_projects()
	village_inventory = ResourceInventory.new(
		VILLAGE_OWNER_ID,
		"Magazzino del Villaggio",
		initial_village_food,
		initial_village_wood,
		initial_village_stone,
		initial_village_coin
	)
	market_inventory = ResourceInventory.new(
		MARKET_OWNER_ID,
		"Emporio del Mercato",
		INITIAL_MARKET_FOOD,
		INITIAL_MARKET_WOOD,
		INITIAL_MARKET_STONE,
		INITIAL_MARKET_COIN
	)
	_reset_flow_dictionaries()
	_sync_npc_inventories()
	if _npc_system != null:
		_npc_system.set_economy_system(self)


func get_system_name() -> String:
	return SYSTEM_NAME


func initialize(start_tick: int) -> void:
	if _initialized:
		return
	_start_tick = maxi(start_tick, 0)
	_last_tick = _start_tick - 1
	_current_day_index = _start_tick / SimulationClock.MINUTES_PER_DAY
	_initialized = true
	_sync_npc_inventories()
	_initial_snapshot = to_dict()
	GameLog.info(TAG, summary())


func on_tick(tick: int, clock: SimulationClock) -> void:
	if not _initialized:
		initialize(tick)
	_sync_npc_inventories()
	var day_index := clock.get_day_index()
	if day_index != _current_day_index:
		_rollover_day(day_index)
	var minute := clock.get_minute_of_day()
	if _npc_system != null:
		for record in _npc_system.get_records():
			_process_worker_tick(record, tick)
			if minute == SUPPER_MINUTE_OF_DAY and not bool(_ate_today.get(record.id, false)):
				_process_evening_ration(record, tick)
	if minute == PROJECT_CHECK_MINUTE_OF_DAY:
		_try_auto_community_project(tick)
	_last_tick = tick


func reset() -> void:
	if not _initialized or _initial_snapshot.is_empty():
		return
	from_dict(_initial_snapshot)


# --- inventories & queries ---------------------------------------------------


func get_inventory(owner_id: String) -> ResourceInventory:
	if owner_id == VILLAGE_OWNER_ID:
		return village_inventory
	if owner_id == MARKET_OWNER_ID:
		return market_inventory
	return npc_inventories.get(owner_id, null) as ResourceInventory


func get_village_resource(resource_id: String) -> int:
	return village_inventory.get_amount(resource_id)


## Returns produced quantity of [param resource_id]. When [param period_only] is
## true, returns the active period flow; otherwise returns the cumulative total.
func get_production(resource_id: String, period_only: bool = false) -> int:
	if not ResourceType.is_valid(resource_id):
		return 0
	if not period_only:
		return int(_total_production.get(resource_id, 0))
	var current := int(_period_production.get(resource_id, 0))
	if current > 0 or not _is_period_empty():
		return current
	return int(_previous_period_production.get(resource_id, 0))


## Returns consumed quantity of [param resource_id]. When [param period_only] is
## true, returns the active period flow; otherwise returns the cumulative total.
func get_consumption(resource_id: String, period_only: bool = false) -> int:
	if not ResourceType.is_valid(resource_id):
		return 0
	if not period_only:
		return int(_total_consumption.get(resource_id, 0))
	var current := int(_period_consumption.get(resource_id, 0))
	if current > 0 or not _is_period_empty():
		return current
	return int(_previous_period_consumption.get(resource_id, 0))


func set_workplace_ready(place_id: String, ready: bool) -> void:
	if not _workplace_prerequisites.has(place_id):
		_workplace_prerequisites[place_id] = {
			"ready": ready,
			"description": "Prerequisito locale (%s)" % place_id,
		}
		return
	var entry: Dictionary = _workplace_prerequisites[place_id]
	entry["ready"] = ready
	_workplace_prerequisites[place_id] = entry


## True when the worker is actually working at their assigned, operational
## workplace and is physically able to work.
func can_worker_produce_now(record: NpcRecord) -> bool:
	if record == null or record.activity != NpcRecord.Activity.WORKING:
		return false
	if record.work_place_id.is_empty() or record.current_place_id != record.work_place_id:
		return false
	if not _is_workplace_ready(record.work_place_id):
		return false
	return (
		record.needs.hunger < EconomyRules.MAX_WORKER_HUNGER_FOR_PRODUCTION
		and record.needs.energy > EconomyRules.MIN_WORKER_ENERGY_FOR_PRODUCTION
	)


func has_shortage(resource_id: String) -> bool:
	if not ResourceType.is_valid(resource_id):
		return false
	if resource_id == ResourceType.FOOD and unfed_meal_attempts_period > 0 \
			and village_inventory.get_amount(ResourceType.FOOD) == 0:
		return true
	return village_inventory.get_amount(resource_id) < ResourceType.shortage_threshold(resource_id)


# --- transactions, transfers & trades ----------------------------------------


## Validated, atomic resource transfer between two registered inventories.
func transfer_resource(
	from_owner: String,
	to_owner: String,
	resource_id: String,
	amount: int,
	tick: int = -1,
	reason: String = "",
	important: bool = true
) -> bool:
	var effective_tick := _effective_tick(tick)
	var from_inv := get_inventory(from_owner)
	var to_inv := get_inventory(to_owner)
	if (
		from_owner.is_empty()
		or to_owner.is_empty()
		or from_owner == to_owner
		or not ResourceType.is_valid(resource_id)
		or amount <= 0
		or from_inv == null
		or to_inv == null
	):
		_record_rejected(
			effective_tick,
			from_owner,
			to_owner,
			resource_id,
			amount,
			"Trasferimento rifiutato: parametri o inventari non validi."
		)
		return false
	if not from_inv.has_amount(resource_id, amount):
		_record_rejected(
			effective_tick,
			from_owner,
			to_owner,
			resource_id,
			amount,
			"Trasferimento rifiutato: %s non possiede %d %s."
			% [from_owner, amount, ResourceType.label_for(resource_id)]
		)
		return false
	from_inv.remove(resource_id, amount)
	to_inv.add(resource_id, amount)
	var text := reason if not reason.is_empty() else (
		"Trasferimento di %d %s da %s a %s"
		% [
			amount,
			ResourceType.label_for(resource_id),
			_owner_label(from_owner),
			_owner_label(to_owner),
		]
	)
	_append_tx(
		effective_tick,
		EconomyTransaction.KIND_TRANSFER,
		from_owner,
		from_owner,
		to_owner,
		resource_id,
		amount,
		0,
		text,
		important
	)
	return true


## Validated, atomic purchase of [param amount] units of [param resource_id] by
## [param buyer_owner] from [param seller_owner] at the documented unit price.
func execute_trade(
	buyer_owner: String,
	seller_owner: String,
	resource_id: String,
	amount: int,
	tick: int = -1,
	custom_unit_price: int = -1,
	actor_id: String = ""
) -> bool:
	var effective_tick := _effective_tick(tick)
	var unit_price := (
		custom_unit_price
		if custom_unit_price > 0
		else ResourceType.base_price(resource_id)
	)
	var buyer_inv := get_inventory(buyer_owner)
	var seller_inv := get_inventory(seller_owner)
	var total_coin := amount * unit_price
	if (
		buyer_owner.is_empty()
		or seller_owner.is_empty()
		or buyer_owner == seller_owner
		or not ResourceType.is_material(resource_id)
		or amount <= 0
		or unit_price <= 0
		or buyer_inv == null
		or seller_inv == null
		or not seller_inv.has_amount(resource_id, amount)
		or not buyer_inv.has_amount(ResourceType.COIN, total_coin)
	):
		_record_rejected(
			effective_tick,
			buyer_owner,
			seller_owner,
			resource_id,
			amount,
			"Scambio rifiutato: parametri o scorte insufficienti."
		)
		return false
	seller_inv.remove(resource_id, amount)
	buyer_inv.remove(ResourceType.COIN, total_coin)
	buyer_inv.add(resource_id, amount)
	seller_inv.add(ResourceType.COIN, total_coin)
	var who := _owner_label(actor_id) if not actor_id.is_empty() else _owner_label(buyer_owner)
	var reason := "%s: scambio %d %s per %d Moneta (%s ↔ %s)" % [
		who,
		amount,
		ResourceType.label_for(resource_id),
		total_coin,
		_owner_label(buyer_owner),
		_owner_label(seller_owner),
	]
	_append_tx(
		effective_tick,
		EconomyTransaction.KIND_TRADE,
		actor_id if not actor_id.is_empty() else buyer_owner,
		seller_owner,
		buyer_owner,
		resource_id,
		amount,
		total_coin,
		reason
	)
	return true


## Validated, atomic barter of two distinct material resources.
func execute_barter(
	first_owner: String,
	second_owner: String,
	give_resource: String,
	give_amount: int,
	take_resource: String,
	take_amount: int,
	tick: int = -1,
	actor_id: String = ""
) -> bool:
	var effective_tick := _effective_tick(tick)
	var first_inv := get_inventory(first_owner)
	var second_inv := get_inventory(second_owner)
	if (
		first_owner.is_empty()
		or second_owner.is_empty()
		or first_owner == second_owner
		or not ResourceType.is_material(give_resource)
		or not ResourceType.is_material(take_resource)
		or give_resource == take_resource
		or give_amount <= 0
		or take_amount <= 0
		or first_inv == null
		or second_inv == null
		or not first_inv.has_amount(give_resource, give_amount)
		or not second_inv.has_amount(take_resource, take_amount)
	):
		_record_rejected(
			effective_tick,
			first_owner,
			second_owner,
			take_resource,
			take_amount,
			"Baratto rifiutato: parametri o scorte insufficienti."
		)
		return false
	first_inv.remove(give_resource, give_amount)
	second_inv.remove(take_resource, take_amount)
	first_inv.add(take_resource, take_amount)
	second_inv.add(give_resource, give_amount)
	var who := _owner_label(actor_id) if not actor_id.is_empty() else _owner_label(first_owner)
	var reason := "%s: baratto %d %s per %d %s" % [
		who,
		give_amount,
		ResourceType.label_for(give_resource),
		take_amount,
		ResourceType.label_for(take_resource),
	]
	_append_tx(
		effective_tick,
		EconomyTransaction.KIND_TRADE,
		actor_id if not actor_id.is_empty() else first_owner,
		second_owner,
		first_owner,
		take_resource,
		take_amount,
		0,
		reason
	)
	return true


## Consumes `FOOD_UNITS_PER_MEAL` (1 Cibo) for [param record], or records a
## shortage and impacts `hunger` and `wellbeing` when no food is available.
func request_meal_for_npc(record: NpcRecord, tick: int = -1) -> bool:
	if record == null:
		return false
	var effective_tick := _effective_tick(tick)
	var needed := EconomyRules.FOOD_UNITS_PER_MEAL
	var npc_inv := get_inventory(record.id)
	if npc_inv != null and npc_inv.has_amount(ResourceType.FOOD, needed):
		npc_inv.remove(ResourceType.FOOD, needed)
		_register_consumption(ResourceType.FOOD, needed)
		_ate_today[record.id] = true
		_append_tx(
			effective_tick,
			EconomyTransaction.KIND_CONSUMPTION,
			record.id,
			record.id,
			"",
			ResourceType.FOOD,
			needed,
			0,
			"%s ha consumato %d Cibo (scorta personale)" % [record.display_name, needed]
		)
		return true
	if village_inventory.has_amount(ResourceType.FOOD, needed):
		var food_price := ResourceType.base_price(ResourceType.FOOD) * needed
		var paid_coin := 0
		if npc_inv != null and npc_inv.has_amount(ResourceType.COIN, food_price):
			npc_inv.remove(ResourceType.COIN, food_price)
			village_inventory.add(ResourceType.COIN, food_price)
			paid_coin = food_price
		village_inventory.remove(ResourceType.FOOD, needed)
		_register_consumption(ResourceType.FOOD, needed)
		_ate_today[record.id] = true
		var suffix := (
			" (%d Moneta versate alla cassa comune)" % paid_coin
			if paid_coin > 0
			else " (dispensa comune)"
		)
		_append_tx(
			effective_tick,
			EconomyTransaction.KIND_CONSUMPTION,
			record.id,
			VILLAGE_OWNER_ID,
			record.id,
			ResourceType.FOOD,
			needed,
			paid_coin,
			"%s ha consumato %d Cibo%s" % [record.display_name, needed, suffix]
		)
		return true
	unfed_meal_attempts_period += 1
	unfed_meal_attempts_total += 1
	record.needs.wellbeing = clampf(
		record.needs.wellbeing - EconomyRules.SHORTAGE_WELLBEING_PENALTY,
		NpcNeeds.MIN_VALUE,
		NpcNeeds.MAX_VALUE
	)
	record.needs.hunger = clampf(
		maxf(record.needs.hunger, EconomyRules.SHORTAGE_HUNGER_FLOOR),
		NpcNeeds.MIN_VALUE,
		NpcNeeds.MAX_VALUE
	)
	_record_rejected(
		effective_tick,
		VILLAGE_OWNER_ID,
		record.id,
		ResourceType.FOOD,
		needed,
		"Carenza di Cibo: %s non ha trovato razioni disponibili" % record.display_name
	)
	return false


## Atomically spends `wood`, `stone` and `coin` from `village_inventory` to
## complete [param project_id].
func fund_project(project_id: String, tick: int = -1) -> bool:
	var effective_tick := _effective_tick(tick)
	var project := _find_project(project_id)
	if (
		project == null
		or (completed_projects.has(project.id) and not project.repeatable)
		or not village_inventory.remove_bundle(project.cost)
	):
		_record_rejected(
			effective_tick,
			VILLAGE_OWNER_ID,
			VILLAGE_OWNER_ID,
			ResourceType.WOOD,
			0,
			"Progetto rifiutato: '%s' non finanziabile." % project_id
		)
		return false
	for resource_id in project.cost.keys():
		var spent := int(project.cost[resource_id])
		if spent > 0 and ResourceType.is_material(String(resource_id)):
			_register_consumption(String(resource_id), spent)
	if not completed_projects.has(project.id):
		completed_projects.append(project.id)
	if not project.bonus_resource.is_empty() and project.bonus_batch_amount > 0:
		_resource_bonus_per_batch[project.bonus_resource] = (
			int(_resource_bonus_per_batch.get(project.bonus_resource, 0))
			+ project.bonus_batch_amount
		)
	if project.wellbeing_boost > 0.0 and _npc_system != null:
		for record in _npc_system.get_records():
			record.needs.wellbeing = clampf(
				record.needs.wellbeing + project.wellbeing_boost,
				NpcNeeds.MIN_VALUE,
				NpcNeeds.MAX_VALUE
			)
	var cost_parts: PackedStringArray = []
	for resource_id in ResourceType.ALL_IDS:
		if project.cost.has(resource_id) and int(project.cost[resource_id]) > 0:
			cost_parts.append(
				"-%d %s" % [int(project.cost[resource_id]), ResourceType.label_for(resource_id)]
			)
	var reason := "Progetto completato: %s (%s)" % [
		project.display_name,
		", ".join(cost_parts),
	]
	_append_tx(
		effective_tick,
		EconomyTransaction.KIND_PROJECT,
		VILLAGE_OWNER_ID,
		VILLAGE_OWNER_ID,
		VILLAGE_OWNER_ID,
		ResourceType.WOOD,
		int(project.cost.get(ResourceType.WOOD, 0)),
		int(project.cost.get(ResourceType.COIN, 0)),
		reason
	)
	return true


# --- validation & serialisation ----------------------------------------------


func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	problems.append_array(village_inventory.validate())
	problems.append_array(market_inventory.validate())
	for npc_id in npc_inventories.keys():
		var inv := npc_inventories[npc_id] as ResourceInventory
		if inv != null:
			problems.append_array(inv.validate())
	return problems


func summary() -> String:
	return "Villaggio: Cibo %d, Legno %d, Pietra %d, Moneta %d | Emporio: Moneta %d" % [
		village_inventory.get_amount(ResourceType.FOOD),
		village_inventory.get_amount(ResourceType.WOOD),
		village_inventory.get_amount(ResourceType.STONE),
		village_inventory.get_amount(ResourceType.COIN),
		market_inventory.get_amount(ResourceType.COIN),
	]


func to_dict() -> Dictionary:
	var npc_inv_data: Dictionary = {}
	for npc_id in npc_inventories.keys():
		var inv := npc_inventories[npc_id] as ResourceInventory
		if inv != null:
			npc_inv_data[npc_id] = inv.to_dict()
	var tx_data: Array = []
	for tx in transactions:
		tx_data.append(tx.to_dict())
	return {
		"initialized": _initialized,
		"start_tick": _start_tick,
		"last_tick": _last_tick,
		"current_day_index": _current_day_index,
		"village_inventory": village_inventory.to_dict(),
		"market_inventory": market_inventory.to_dict(),
		"npc_inventories": npc_inv_data,
		"work_progress": _work_progress.duplicate(true),
		"workplace_prerequisites": _workplace_prerequisites.duplicate(true),
		"completed_projects": completed_projects.duplicate(),
		"resource_bonus_per_batch": _resource_bonus_per_batch.duplicate(true),
		"period_production": _period_production.duplicate(true),
		"period_consumption": _period_consumption.duplicate(true),
		"previous_period_production": _previous_period_production.duplicate(true),
		"previous_period_consumption": _previous_period_consumption.duplicate(true),
		"total_production": _total_production.duplicate(true),
		"total_consumption": _total_consumption.duplicate(true),
		"unfed_meal_attempts_period": unfed_meal_attempts_period,
		"unfed_meal_attempts_total": unfed_meal_attempts_total,
		"ate_today": _ate_today.duplicate(true),
		"next_transaction_id": _next_transaction_id,
		"rejected_transaction_count": rejected_transaction_count,
		"transactions": tx_data,
	}


func from_dict(data: Dictionary) -> void:
	_initialized = bool(data.get("initialized", true))
	_start_tick = int(data.get("start_tick", 0))
	_last_tick = int(data.get("last_tick", -1))
	_current_day_index = int(data.get("current_day_index", 0))
	village_inventory.from_dict(data.get("village_inventory", {}))
	market_inventory.from_dict(data.get("market_inventory", {}))
	npc_inventories.clear()
	var npc_inv_data: Dictionary = data.get("npc_inventories", {})
	for npc_id in npc_inv_data.keys():
		var inv := ResourceInventory.new(String(npc_id))
		inv.from_dict(npc_inv_data[npc_id] as Dictionary)
		npc_inventories[String(npc_id)] = inv
	_work_progress = (data.get("work_progress", {}) as Dictionary).duplicate(true)
	_workplace_prerequisites = (
		data.get("workplace_prerequisites", EconomyRules.default_workplace_prerequisites())
		as Dictionary
	).duplicate(true)
	completed_projects = PackedStringArray(data.get("completed_projects", []))
	_resource_bonus_per_batch = (
		data.get("resource_bonus_per_batch", {}) as Dictionary
	).duplicate(true)
	_period_production = (data.get("period_production", {}) as Dictionary).duplicate(true)
	_period_consumption = (data.get("period_consumption", {}) as Dictionary).duplicate(true)
	_previous_period_production = (
		data.get("previous_period_production", {}) as Dictionary
	).duplicate(true)
	_previous_period_consumption = (
		data.get("previous_period_consumption", {}) as Dictionary
	).duplicate(true)
	_total_production = (data.get("total_production", {}) as Dictionary).duplicate(true)
	_total_consumption = (data.get("total_consumption", {}) as Dictionary).duplicate(true)
	unfed_meal_attempts_period = int(data.get("unfed_meal_attempts_period", 0))
	unfed_meal_attempts_total = int(data.get("unfed_meal_attempts_total", 0))
	_ate_today = (data.get("ate_today", {}) as Dictionary).duplicate(true)
	_next_transaction_id = int(data.get("next_transaction_id", 1))
	rejected_transaction_count = int(data.get("rejected_transaction_count", 0))
	transactions.clear()
	for tx_dict in data.get("transactions", []):
		var tx := EconomyTransaction.new()
		tx.from_dict(tx_dict as Dictionary)
		transactions.append(tx)
	_sync_npc_inventories()


# --- internals ---------------------------------------------------------------


func _is_workplace_ready(place_id: String) -> bool:
	if not _workplace_prerequisites.has(place_id):
		return false
	var entry: Dictionary = _workplace_prerequisites[place_id]
	return bool(entry.get("ready", false))


func _process_worker_tick(record: NpcRecord, tick: int) -> void:
	if not can_worker_produce_now(record):
		return
	var rule := _profession_rules.get(record.profession_id, null) as EconomyRules.ProfessionRule
	if rule == null:
		return
	var progress := int(_work_progress.get(record.id, 0)) + 1
	if progress < rule.minutes_per_batch:
		_work_progress[record.id] = progress
		return
	_work_progress[record.id] = progress - rule.minutes_per_batch
	if rule.is_producer():
		_complete_production_batch(record, rule, tick)
	elif rule.facilitates_trade:
		_run_merchant_brokerage(record, tick)


func _complete_production_batch(
	record: NpcRecord, rule: EconomyRules.ProfessionRule, tick: int
) -> void:
	var resource_id := rule.produces_resource
	var bonus := int(_resource_bonus_per_batch.get(resource_id, 0))
	var produced := rule.batch_amount + bonus
	if produced <= 0 or not ResourceType.is_valid(resource_id):
		return
	village_inventory.add(resource_id, produced)
	_register_production(resource_id, produced)
	var wage_paid := 0
	var npc_inv := get_inventory(record.id)
	if (
		npc_inv != null
		and rule.wage_per_batch > 0
		and village_inventory.has_amount(ResourceType.COIN, rule.wage_per_batch)
	):
		village_inventory.remove(ResourceType.COIN, rule.wage_per_batch)
		npc_inv.add(ResourceType.COIN, rule.wage_per_batch)
		wage_paid = rule.wage_per_batch
	var reason := "%s (%s) ha prodotto +%d %s" % [
		record.display_name,
		record.profession_label.to_lower(),
		produced,
		ResourceType.label_for(resource_id),
	]
	_append_tx(
		tick,
		EconomyTransaction.KIND_PRODUCTION,
		record.id,
		record.id,
		VILLAGE_OWNER_ID,
		resource_id,
		produced,
		wage_paid,
		reason
	)


func _run_merchant_brokerage(merchant: NpcRecord, tick: int) -> void:
	if _npc_system != null:
		for record in _npc_system.get_records():
			var npc_inv := get_inventory(record.id)
			if npc_inv == null:
				continue
			for resource_id in ResourceType.MATERIAL_IDS:
				var held := npc_inv.get_amount(resource_id)
				if held <= 0:
					continue
				var unit_price := ResourceType.base_price(resource_id)
				if village_inventory.has_amount(ResourceType.COIN, held * unit_price):
					execute_trade(
						VILLAGE_OWNER_ID,
						record.id,
						resource_id,
						held,
						tick,
						unit_price,
						merchant.id
					)
					return
				if transfer_resource(
					record.id,
					VILLAGE_OWNER_ID,
					resource_id,
					held,
					tick,
					"%s ha raccolto %d %s da %s per il magazzino"
					% [
						merchant.display_name,
						held,
						ResourceType.label_for(resource_id),
						record.display_name,
					],
					true
				):
					return
	if village_inventory.get_amount(ResourceType.FOOD) < 16 \
			and market_inventory.has_amount(ResourceType.FOOD, 2):
		var food_cost := 2 * ResourceType.base_price(ResourceType.FOOD)
		if village_inventory.has_amount(ResourceType.COIN, food_cost):
			execute_trade(
				VILLAGE_OWNER_ID,
				MARKET_OWNER_ID,
				ResourceType.FOOD,
				2,
				tick,
				ResourceType.base_price(ResourceType.FOOD),
				merchant.id
			)
			return
		if village_inventory.has_amount(ResourceType.STONE, 6):
			execute_barter(
				VILLAGE_OWNER_ID,
				MARKET_OWNER_ID,
				ResourceType.STONE,
				1,
				ResourceType.FOOD,
				2,
				tick,
				merchant.id
			)
			return
	if village_inventory.get_amount(ResourceType.WOOD) > 16 \
			and market_inventory.has_amount(
				ResourceType.COIN, 2 * ResourceType.base_price(ResourceType.WOOD)
			):
		execute_trade(
			MARKET_OWNER_ID,
			VILLAGE_OWNER_ID,
			ResourceType.WOOD,
			2,
			tick,
			ResourceType.base_price(ResourceType.WOOD),
			merchant.id
		)
		return
	if village_inventory.get_amount(ResourceType.STONE) > 14 \
			and market_inventory.has_amount(
				ResourceType.COIN, 2 * ResourceType.base_price(ResourceType.STONE)
			):
		execute_trade(
			MARKET_OWNER_ID,
			VILLAGE_OWNER_ID,
			ResourceType.STONE,
			2,
			tick,
			ResourceType.base_price(ResourceType.STONE),
			merchant.id
		)


func _process_evening_ration(record: NpcRecord, tick: int) -> void:
	var fed := request_meal_for_npc(record, tick)
	if fed:
		record.needs.hunger = clampf(
			record.needs.hunger - 24.0, NpcNeeds.MIN_VALUE, NpcNeeds.MAX_VALUE
		)
		record.needs.wellbeing = clampf(
			record.needs.wellbeing + 1.5, NpcNeeds.MIN_VALUE, NpcNeeds.MAX_VALUE
		)


func _try_auto_community_project(tick: int) -> void:
	var project := EconomyRules.next_available_project(_projects, completed_projects)
	if project == null:
		return
	var needed_wood := int(project.cost.get(ResourceType.WOOD, 0))
	var needed_stone := int(project.cost.get(ResourceType.STONE, 0))
	var needed_coin := int(project.cost.get(ResourceType.COIN, 0))
	if (
		village_inventory.get_amount(ResourceType.WOOD)
		>= needed_wood + EconomyRules.PROJECT_RESERVE_WOOD
		and village_inventory.get_amount(ResourceType.STONE)
		>= needed_stone + EconomyRules.PROJECT_RESERVE_STONE
		and village_inventory.get_amount(ResourceType.COIN)
		>= needed_coin + EconomyRules.PROJECT_RESERVE_COIN
	):
		fund_project(project.id, tick)


func _rollover_day(new_day_index: int) -> void:
	_current_day_index = new_day_index
	_previous_period_production = _period_production.duplicate(true)
	_previous_period_consumption = _period_consumption.duplicate(true)
	for resource_id in ResourceType.ALL_IDS:
		_period_production[resource_id] = 0
		_period_consumption[resource_id] = 0
	unfed_meal_attempts_period = 0
	_ate_today.clear()


func _is_period_empty() -> bool:
	for resource_id in ResourceType.ALL_IDS:
		if int(_period_production.get(resource_id, 0)) > 0:
			return false
		if int(_period_consumption.get(resource_id, 0)) > 0:
			return false
	return true


func _register_production(resource_id: String, amount: int) -> void:
	_period_production[resource_id] = int(_period_production.get(resource_id, 0)) + amount
	_total_production[resource_id] = int(_total_production.get(resource_id, 0)) + amount


func _register_consumption(resource_id: String, amount: int) -> void:
	_period_consumption[resource_id] = int(_period_consumption.get(resource_id, 0)) + amount
	_total_consumption[resource_id] = int(_total_consumption.get(resource_id, 0)) + amount


func _reset_flow_dictionaries() -> void:
	for resource_id in ResourceType.ALL_IDS:
		_period_production[resource_id] = 0
		_period_consumption[resource_id] = 0
		_previous_period_production[resource_id] = 0
		_previous_period_consumption[resource_id] = 0
		_total_production[resource_id] = 0
		_total_consumption[resource_id] = 0
		_resource_bonus_per_batch[resource_id] = 0


func _sync_npc_inventories() -> void:
	if _npc_system == null:
		return
	for record in _npc_system.get_records():
		if not npc_inventories.has(record.id):
			npc_inventories[record.id] = ResourceInventory.new(
				record.id,
				"Sacca di %s" % record.display_name,
				0,
				0,
				0,
				INITIAL_NPC_COIN
			)
		if not _work_progress.has(record.id):
			_work_progress[record.id] = 0


func _find_project(project_id: String) -> EconomyRules.CommunityProject:
	for project in _projects:
		if project.id == project_id:
			return project
	return null


func _owner_label(owner_id: String) -> String:
	if owner_id == VILLAGE_OWNER_ID:
		return "Villaggio"
	if owner_id == MARKET_OWNER_ID:
		return "Mercato"
	if _npc_system != null:
		var record := _npc_system.get_record(owner_id)
		if record != null:
			return record.display_name
	return owner_id


func _effective_tick(tick: int) -> int:
	if tick >= 0:
		return tick
	return maxi(_last_tick, _start_tick)


func _record_rejected(
	tick: int,
	from_owner: String,
	to_owner: String,
	resource_id: String,
	amount: int,
	reason: String
) -> void:
	rejected_transaction_count += 1
	_append_tx(
		tick,
		EconomyTransaction.KIND_REJECTED,
		from_owner,
		from_owner,
		to_owner,
		resource_id,
		amount,
		0,
		reason
	)


func _append_tx(
	tick: int,
	kind: String,
	actor_id: String,
	from_owner: String,
	to_owner: String,
	resource_id: String,
	amount: int,
	coin_amount: int,
	reason: String,
	important: bool = true
) -> void:
	var tx := EconomyTransaction.new(
		_next_transaction_id,
		tick,
		kind,
		actor_id,
		from_owner,
		to_owner,
		resource_id,
		amount,
		reason
	)
	tx.coin_amount = coin_amount
	tx.important = important
	_next_transaction_id += 1
	transactions.append(tx)
	while transactions.size() > MAX_TRANSACTION_HISTORY:
		transactions.remove_at(0)
