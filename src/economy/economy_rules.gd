class_name EconomyRules
extends RefCounted
## Pure-data rules for professions, workplace prerequisites, food consumption,
## exchange pricing and community projects.
##
## Keeping all production rates, prerequisites and project costs in one module
## makes the economic formulas easy to inspect, document and assert in unit
## tests without reading the simulation loop.

const FOOD_UNITS_PER_MEAL := 1
const MERCHANT_WORK_MINUTES_PER_TRADE := 60
const MAX_WORKER_HUNGER_FOR_PRODUCTION := 92.0
const MIN_WORKER_ENERGY_FOR_PRODUCTION := 5.0

## When the village has no food left, an eating attempt cannot reduce hunger
## below this threshold and applies a wellbeing penalty instead of mortality.
const SHORTAGE_HUNGER_FLOOR := 76.0
const SHORTAGE_WELLBEING_PENALTY := 4.5
const SHORTAGE_DAILY_WELLBEING_DRIFT := -0.05

## Minimum reserves kept in the village storehouse before automatic community
## projects spend excess wood, stone and coin.
const PROJECT_RESERVE_WOOD := 6
const PROJECT_RESERVE_STONE := 6
const PROJECT_RESERVE_COIN := 10


class ProfessionRule extends RefCounted:
	var profession_id: String = ""
	var label: String = ""
	var produces_resource: String = ""
	var minutes_per_batch: int = 60
	var batch_amount: int = 0
	var wage_per_batch: int = 1
	var facilitates_trade: bool = false
	var required_workplace_id: String = ""
	var prerequisite_name: String = ""

	func _init(
		initial_profession_id: String = "",
		initial_label: String = "",
		initial_resource: String = "",
		initial_minutes: int = 60,
		initial_amount: int = 0,
		initial_wage: int = 1,
		initial_trade: bool = false,
		initial_workplace: String = "",
		initial_prerequisite: String = ""
	) -> void:
		profession_id = initial_profession_id
		label = initial_label
		produces_resource = initial_resource
		minutes_per_batch = maxi(initial_minutes, 1)
		batch_amount = maxi(initial_amount, 0)
		wage_per_batch = maxi(initial_wage, 0)
		facilitates_trade = initial_trade
		required_workplace_id = initial_workplace
		prerequisite_name = initial_prerequisite

	func is_producer() -> bool:
		return not produces_resource.is_empty() and batch_amount > 0


class CommunityProject extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var description: String = ""
	var cost: Dictionary = {}
	var bonus_resource: String = ""
	var bonus_batch_amount: int = 0
	var wellbeing_boost: float = 0.0
	var repeatable: bool = false

	func _init(
		initial_id: String = "",
		initial_name: String = "",
		initial_description: String = "",
		initial_cost: Dictionary = {},
		initial_bonus_resource: String = "",
		initial_bonus_amount: int = 0,
		initial_wellbeing_boost: float = 0.0,
		initial_repeatable: bool = false
	) -> void:
		id = initial_id
		display_name = initial_name
		description = initial_description
		cost = initial_cost.duplicate()
		bonus_resource = initial_bonus_resource
		bonus_batch_amount = maxi(initial_bonus_amount, 0)
		wellbeing_boost = maxf(initial_wellbeing_boost, 0.0)
		repeatable = initial_repeatable


static func build_profession_rules() -> Dictionary:
	var table: Dictionary = {}
	var entries := [
		ProfessionRule.new(
			"farmer",
			"Agricoltore",
			ResourceType.FOOD,
			60,
			3,
			2,
			false,
			"work_field",
			"Campi coltivati e attrezzi agricoli"
		),
		ProfessionRule.new(
			"forager",
			"Raccoglitrice",
			ResourceType.FOOD,
			60,
			2,
			1,
			false,
			"work_garden",
			"Orto botanico e cesti di raccolta"
		),
		ProfessionRule.new(
			"fisher",
			"Pescatore",
			ResourceType.FOOD,
			60,
			2,
			1,
			false,
			"work_pond",
			"Riva dello stagno e reti da pesca"
		),
		ProfessionRule.new(
			"baker",
			"Panettiera",
			ResourceType.FOOD,
			60,
			2,
			1,
			false,
			"work_market",
			"Forno da pane e banco delle farine"
		),
		ProfessionRule.new(
			"innkeeper",
			"Locandiera",
			ResourceType.FOOD,
			75,
			2,
			1,
			false,
			"work_inn",
			"Cucina della locanda e dispensa"
		),
		ProfessionRule.new(
			"farmhand",
			"Bracciante",
			ResourceType.FOOD,
			60,
			2,
			1,
			false,
			"work_field",
			"Campi coltivati e attrezzi agricoli"
		),
		ProfessionRule.new(
			"cook",
			"Cuciniera",
			ResourceType.FOOD,
			60,
			2,
			1,
			false,
			"work_inn",
			"Cucina della locanda e dispensa"
		),
		ProfessionRule.new(
			"shepherd",
			"Pastore",
			ResourceType.FOOD,
			60,
			2,
			1,
			false,
			"work_field",
			"Pascolo recintato"
		),
		ProfessionRule.new(
			"gardener",
			"Giardiniera",
			ResourceType.FOOD,
			60,
			2,
			1,
			false,
			"work_garden",
			"Orto botanico e cesti di raccolta"
		),
		ProfessionRule.new(
			"woodcutter",
			"Boscaiolo",
			ResourceType.WOOD,
			60,
			2,
			2,
			false,
			"work_workshop",
			"Ceppo da taglio e asce da boscaiolo"
		),
		ProfessionRule.new(
			"carpenter",
			"Falegname",
			ResourceType.WOOD,
			60,
			2,
			2,
			false,
			"work_workshop",
			"Banco da falegname e seghe"
		),
		ProfessionRule.new(
			"quarry_worker",
			"Cavatore",
			ResourceType.STONE,
			60,
			2,
			2,
			false,
			"work_forge",
			"Banco d'estrazione e picconi da roccia"
		),
		ProfessionRule.new(
			"miner",
			"Minatore",
			ResourceType.STONE,
			60,
			2,
			2,
			false,
			"work_forge",
			"Banco d'estrazione e picconi da roccia"
		),
		ProfessionRule.new(
			"blacksmith",
			"Fabbro",
			ResourceType.STONE,
			75,
			2,
			2,
			false,
			"work_forge",
			"Fucina accesa e mazze da spacco"
		),
		ProfessionRule.new(
			"potter",
			"Vasaio",
			ResourceType.STONE,
			75,
			2,
			1,
			false,
			"work_workshop",
			"Tornio e forno da terracotta"
		),
		ProfessionRule.new(
			"merchant",
			"Mercante",
			"",
			MERCHANT_WORK_MINUTES_PER_TRADE,
			0,
			1,
			true,
			"work_market",
			"Banco del mercato, registri e bilancia"
		),
		ProfessionRule.new(
			"clerk",
			"Cancelliera",
			"",
			60,
			0,
			1,
			false,
			"work_hall",
			"Registri della Sala del Consiglio"
		),
		ProfessionRule.new(
			"archivist",
			"Archivista",
			"",
			60,
			0,
			1,
			false,
			"work_hall",
			"Archivio comunale"
		),
		ProfessionRule.new(
			"healer",
			"Guaritrice",
			ResourceType.FOOD,
			75,
			1,
			1,
			false,
			"work_garden",
			"Erbario e mortaio"
		),
		ProfessionRule.new(
			"weaver",
			"Tessitrice",
			"",
			60,
			0,
			1,
			false,
			"work_market",
			"Telaio da banco"
		),
	]
	for rule in entries:
		table[rule.profession_id] = rule
	return table


static func default_workplace_prerequisites() -> Dictionary:
	return {
		"work_field": {
			"ready": true,
			"description": "Campi dissodati e attrezzi agricoli",
		},
		"work_garden": {
			"ready": true,
			"description": "Orto recintato e cesti di raccolta",
		},
		"work_pond": {
			"ready": true,
			"description": "Pontile dello stagno e reti da pesca",
		},
		"work_market": {
			"ready": true,
			"description": "Bancarelle del mercato, forno e bilancia",
		},
		"work_inn": {
			"ready": true,
			"description": "Cucina della locanda e dispensa",
		},
		"work_workshop": {
			"ready": true,
			"description": "Ceppo da taglio, cavalletto e asce da boscaiolo",
		},
		"work_forge": {
			"ready": true,
			"description": "Deposito di scavo, picconi e banco della pietra",
		},
		"work_hall": {
			"ready": true,
			"description": "Sala del Consiglio e registri civici",
		},
	}


static func build_community_projects() -> Array[CommunityProject]:
	var projects: Array[CommunityProject] = [
		CommunityProject.new(
			"granary_repair",
			"Rinforzo del Granaio Comune",
			"Rinforza tetto e basamento del granaio (+1 Cibo per lotto agricolo).",
			{
				ResourceType.WOOD: 6,
				ResourceType.STONE: 4,
				ResourceType.COIN: 8,
			},
			ResourceType.FOOD,
			1,
			2.0,
			false
		),
		CommunityProject.new(
			"logging_trestle",
			"Cavalletto della Segheria",
			"Costruisce un cavalletto rinforzato (+1 Legno per lotto di taglio).",
			{
				ResourceType.WOOD: 8,
				ResourceType.STONE: 4,
				ResourceType.COIN: 6,
			},
			ResourceType.WOOD,
			1,
			1.5,
			false
		),
		CommunityProject.new(
			"quarry_shoring",
			"Armatura del Banco di Pietra",
			"Mette in sicurezza il fronte di scavo (+1 Pietra per lotto estratto).",
			{
				ResourceType.WOOD: 6,
				ResourceType.STONE: 8,
				ResourceType.COIN: 8,
			},
			ResourceType.STONE,
			1,
			1.5,
			false
		),
		CommunityProject.new(
			"well_maintenance",
			"Manutenzione del Pozzo e della Piazza",
			"Ripara carrucola, tettoia e lastricato (+3 benessere agli abitanti).",
			{
				ResourceType.WOOD: 4,
				ResourceType.STONE: 4,
				ResourceType.COIN: 4,
			},
			"",
			0,
			3.0,
			true
		),
	]
	return projects


static func next_available_project(
	projects: Array[CommunityProject], completed_ids: PackedStringArray
) -> CommunityProject:
	for project in projects:
		if not completed_ids.has(project.id):
			return project
	for project in projects:
		if project.repeatable:
			return project
	return null


static func can_fund_project(economy: EconomySystem, project_id: String) -> bool:
	if economy == null:
		return false
	for project in build_community_projects():
		if project.id != project_id:
			continue
		if economy.completed_projects.has(project.id) and not project.repeatable:
			return false
		return economy.village_inventory.has_bundle(project.cost)
	return false


static func format_shortages(economy: EconomySystem) -> String:
	if economy == null:
		return "Nessuna carenza attiva"
	var items: PackedStringArray = []
	for resource_id in ResourceType.ALL_IDS:
		var amount := economy.get_village_resource(resource_id)
		var threshold := ResourceType.shortage_threshold(resource_id)
		var label := ResourceType.label_for(resource_id)
		if (
			resource_id == ResourceType.FOOD
			and amount == 0
			and economy.unfed_meal_attempts_period > 0
		):
			items.append(
				"Carenza critica di %s (0 disponibili, %d pasti non soddisfatti)"
				% [label, economy.unfed_meal_attempts_period]
			)
		elif amount == 0:
			items.append("Scorte esaurite di %s (0/%d)" % [label, threshold])
		elif amount < threshold:
			items.append("Scorte basse di %s (%d/%d)" % [label, amount, threshold])
	if items.is_empty():
		return "Nessuna carenza attiva"
	return " · ".join(items)


static func format_projects(economy: EconomySystem) -> String:
	if economy == null:
		return "Progetti: —"
	var projects := build_community_projects()
	var next_project := next_available_project(projects, economy.completed_projects)
	var completed_count := economy.completed_projects.size()
	if next_project == null:
		return "Progetti completati: %d/%d" % [completed_count, projects.size()]
	var cost_parts: PackedStringArray = []
	for resource_id in ResourceType.ALL_IDS:
		if next_project.cost.has(resource_id):
			cost_parts.append(
				"%d %s" % [int(next_project.cost[resource_id]), ResourceType.label_for(resource_id)]
			)
	return "Progetti: %d/%d · Prossimo: %s (%s)" % [
		completed_count,
		projects.size(),
		next_project.display_name,
		", ".join(cost_parts),
	]


static func total_system_resource(economy: EconomySystem, resource_id: String) -> int:
	if economy == null:
		return 0
	var total := (
		economy.village_inventory.get_amount(resource_id)
		+ economy.market_inventory.get_amount(resource_id)
	)
	for npc_id in economy.npc_inventories.keys():
		var inv := economy.npc_inventories[npc_id] as ResourceInventory
		if inv != null:
			total += inv.get_amount(resource_id)
	return total


static func has_available_food_for(economy: EconomySystem, npc_id: String = "") -> bool:
	if economy == null:
		return false
	if not npc_id.is_empty():
		var inv := economy.get_inventory(npc_id)
		if inv != null and inv.get_amount(ResourceType.FOOD) >= FOOD_UNITS_PER_MEAL:
			return true
	return economy.village_inventory.get_amount(ResourceType.FOOD) >= FOOD_UNITS_PER_MEAL


static func recent_transactions(
	economy: EconomySystem, limit: int = 5, important_only: bool = true
) -> Array[EconomyTransaction]:
	var result: Array[EconomyTransaction] = []
	if economy == null or limit <= 0:
		return result
	var index := economy.transactions.size() - 1
	while index >= 0 and result.size() < limit:
		var tx := economy.transactions[index]
		if not important_only or tx.important:
			result.append(tx)
		index -= 1
	return result
