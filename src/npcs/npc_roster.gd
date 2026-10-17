class_name NpcRoster
extends RefCounted
## Deterministic starting population of Everafter.
##
## The roster is a fixed table on purpose: the same names, ages, professions
## and personalities are created on every run, regardless of wall clock, RNG
## state or frame rate. The only variable is how many entries are requested,
## which comes from `GameConfig.npc_population_size` (default 10). This is what
## makes the inhabitants recognisable between sessions before persistence
## exists; later a save file can replace the table without changing the records.
##
## Every entry owns a distinct set of initial needs and personality values.
## Relationships and memories are seeded here but **not simulated** yet: they
## are the data shape the social and chronicle phases will grow into.

const MAX_POPULATION := 16

## Fixed catalogue. Work minutes are minutes since midnight.
## `work_place_id` must exist in the place registry built by the world.
static var _catalog := [
	{
		"name": "Elio Sartori", "age": 38,
		"profession_id": "farmer", "profession": "Agricoltore",
		"work_place_id": "work_field", "work_start": 390, "work_end": 780,
		"color": Color(0.47, 0.6, 0.32),
		"diligence": 82, "sociability": 44, "curiosity": 51, "calmness": 73,
		"energy": 92.0, "hunger": 21.0, "wellbeing": 76.0,
		"memory": "Ha imparato a leggere il cielo prima ancora a leggere le lettere.",
	},
	{
		"name": "Mira Bellandi", "age": 45,
		"profession_id": "innkeeper", "profession": "Locandiera",
		"work_place_id": "work_inn", "work_start": 540, "work_end": 1380,
		"color": Color(0.72, 0.43, 0.3),
		"diligence": 76, "sociability": 91, "curiosity": 63, "calmness": 68,
		"energy": 84.0, "hunger": 35.0, "wellbeing": 81.0,
		"memory": "Ricorda la prima notte in cui la locanda rimase piena fino all'alba.",
	},
	{
		"name": "Tullio Fabbri", "age": 52,
		"profession_id": "merchant", "profession": "Mercante",
		"work_place_id": "work_market", "work_start": 510, "work_end": 1080,
		"color": Color(0.78, 0.63, 0.26),
		"diligence": 69, "sociability": 84, "curiosity": 72, "calmness": 55,
		"energy": 78.0, "hunger": 44.0, "wellbeing": 69.0,
		"memory": "Sa riconoscere una buona moneta dal suono che fa sul banco.",
	},
	{
		"name": "Neria Corvi", "age": 34,
		"profession_id": "clerk", "profession": "Cancelliera",
		"work_place_id": "work_hall", "work_start": 480, "work_end": 960,
		"color": Color(0.42, 0.52, 0.7),
		"diligence": 88, "sociability": 37, "curiosity": 83, "calmness": 79,
		"energy": 73.0, "hunger": 18.0, "wellbeing": 72.0,
		"memory": "Conserva una copia di ogni decisione del Consiglio dell'ultimo anno.",
	},
	{
		"name": "Bruno Ferrante", "age": 41,
		"profession_id": "quarry_worker", "profession": "Cavatore",
		"work_place_id": "work_forge", "work_start": 450, "work_end": 990,
		"color": Color(0.55, 0.36, 0.28),
		"diligence": 91, "sociability": 49, "curiosity": 39, "calmness": 61,
		"energy": 96.0, "hunger": 52.0, "wellbeing": 64.0,
		"memory": "Porta ancora la cicatrice del primo piccone che si è fabbricato.",
	},
	{
		"name": "Iside Malaspina", "age": 29,
		"profession_id": "forager", "profession": "Raccoglitrice",
		"work_place_id": "work_garden", "work_start": 540, "work_end": 900,
		"color": Color(0.48, 0.68, 0.48),
		"diligence": 74, "sociability": 67, "curiosity": 94, "calmness": 86,
		"energy": 81.0, "hunger": 27.0, "wellbeing": 85.0,
		"memory": "Conosce le erbe e le bacche della valle meglio dei sentieri che ci portano.",
	},
	{
		"name": "Cecco Palumbo", "age": 57,
		"profession_id": "fisher", "profession": "Pescatore",
		"work_place_id": "work_pond", "work_start": 330, "work_end": 750,
		"color": Color(0.35, 0.58, 0.63),
		"diligence": 62, "sociability": 32, "curiosity": 58, "calmness": 90,
		"energy": 88.0, "hunger": 39.0, "wellbeing": 78.0,
		"memory": "Dice che lo stagno parla solo a chi sa stare zitto abbastanza a lungo.",
	},
	{
		"name": "Livia Orsini", "age": 26,
		"profession_id": "weaver", "profession": "Tessitrice",
		"work_place_id": "work_market", "work_start": 540, "work_end": 1020,
		"color": Color(0.66, 0.45, 0.66),
		"diligence": 71, "sociability": 78, "curiosity": 64, "calmness": 59,
		"energy": 69.0, "hunger": 31.0, "wellbeing": 67.0,
		"memory": "Ha tessuto il drappo che pende nella Sala del Consiglio.",
	},
	{
		"name": "Odo Grimaldi", "age": 63,
		"profession_id": "woodcutter", "profession": "Boscaiolo",
		"work_place_id": "work_workshop", "work_start": 420, "work_end": 900,
		"color": Color(0.6, 0.47, 0.3),
		"diligence": 79, "sociability": 57, "curiosity": 45, "calmness": 82,
		"energy": 64.0, "hunger": 47.0, "wellbeing": 61.0,
		"memory": "Ricorda di aver tagliato le travi per il tetto della locanda tre inverni fa.",
	},
	{
		"name": "Rosa Denti", "age": 31,
		"profession_id": "baker", "profession": "Panettiera",
		"work_place_id": "work_market", "work_start": 270, "work_end": 720,
		"color": Color(0.83, 0.7, 0.45),
		"diligence": 86, "sociability": 73, "curiosity": 41, "calmness": 64,
		"energy": 58.0, "hunger": 56.0, "wellbeing": 58.0,
		"memory": "Si alza prima di tutti e conosce il sapore del pane ancora caldo.",
	},
	{
		"name": "Vito Lanari", "age": 48,
		"profession_id": "farmhand", "profession": "Bracciante",
		"work_place_id": "work_field", "work_start": 360, "work_end": 840,
		"color": Color(0.57, 0.56, 0.3),
		"diligence": 65, "sociability": 61, "curiosity": 33, "calmness": 58,
		"energy": 87.0, "hunger": 62.0, "wellbeing": 55.0,
		"memory": "Sa quale angolo del campo resta all'ombra anche a mezzogiorno.",
	},
	{
		"name": "Ada Sorrentino", "age": 37,
		"profession_id": "archivist", "profession": "Archivista",
		"work_place_id": "work_hall", "work_start": 510, "work_end": 990,
		"color": Color(0.44, 0.43, 0.62),
		"diligence": 81, "sociability": 46, "curiosity": 89, "calmness": 75,
		"energy": 76.0, "hunger": 24.0, "wellbeing": 73.0,
		"memory": "Ha letto la cronaca del villaggio fino alla pagina ingiallita dal tempo.",
	},
	{
		"name": "Milo Peruzzi", "age": 24,
		"profession_id": "potter", "profession": "Vasaio",
		"work_place_id": "work_workshop", "work_start": 480, "work_end": 960,
		"color": Color(0.68, 0.52, 0.36),
		"diligence": 58, "sociability": 64, "curiosity": 77, "calmness": 48,
		"energy": 94.0, "hunger": 29.0, "wellbeing": 80.0,
		"memory": "Tiene da parte una ciotola storta: la prima che ha fatto da solo.",
	},
	{
		"name": "Elsa Rinaldi", "age": 54,
		"profession_id": "cook", "profession": "Cuciniera",
		"work_place_id": "work_inn", "work_start": 600, "work_end": 1320,
		"color": Color(0.74, 0.55, 0.36),
		"diligence": 84, "sociability": 80, "curiosity": 52, "calmness": 71,
		"energy": 72.0, "hunger": 41.0, "wellbeing": 77.0,
		"memory": "Conosce la ricetta dello stufato che fa restare i viandanti un giorno in più.",
	},
	{
		"name": "Fabio Neri", "age": 33,
		"profession_id": "shepherd", "profession": "Pastore",
		"work_place_id": "work_field", "work_start": 330, "work_end": 810,
		"color": Color(0.5, 0.62, 0.55),
		"diligence": 61, "sociability": 39, "curiosity": 48, "calmness": 88,
		"energy": 90.0, "hunger": 33.0, "wellbeing": 74.0,
		"memory": "Si è addormentato una volta sul prato e si è svegliato circondato dalle capre.",
	},
	{
		"name": "Celia Monti", "age": 27,
		"profession_id": "gardener", "profession": "Giardiniera",
		"work_place_id": "work_garden", "work_start": 420, "work_end": 1020,
		"color": Color(0.58, 0.72, 0.4),
		"diligence": 77, "sociability": 69, "curiosity": 71, "calmness": 66,
		"energy": 83.0, "hunger": 26.0, "wellbeing": 82.0,
		"memory": "Ha piantato il primo melo del giardino comune e ne controlla le foglie ogni mattina.",
	},
]


## Builds [param count] stable inhabitants. The number is clamped to the size of
## the fixed catalogue; the caller (the world) owns the configured value.
static func build(count: int) -> Array[NpcRecord]:
	var wanted := clampi(count, 0, _catalog.size())
	if count > _catalog.size():
		push_warning(
			"NpcRoster: requested %d inhabitants, the catalogue holds %d."
			% [count, _catalog.size()]
		)
	var records: Array[NpcRecord] = []
	for index in wanted:
		var entry: Dictionary = _catalog[index]
		var record := NpcRecord.new()
		record.id = "npc_%03d" % (index + 1)
		record.display_name = String(entry["name"])
		record.age = int(entry["age"])
		record.profession_id = String(entry["profession_id"])
		record.profession_label = String(entry["profession"])
		record.profession_color = entry["color"]
		record.work_place_id = String(entry["work_place_id"])
		record.work_start_minute = int(entry["work_start"])
		record.work_end_minute = int(entry["work_end"])
		record.personality = NpcPersonality.new(
			int(entry["diligence"]),
			int(entry["sociability"]),
			int(entry["curiosity"]),
			int(entry["calmness"])
		)
		record.needs = NpcNeeds.new(
			float(entry["energy"]), float(entry["hunger"]), float(entry["wellbeing"])
		)
		record.memories.append({
			"kind": "origin",
			"text": String(entry["memory"]),
			"tick": 0,
		})
		record.memories.append({
			"kind": "home",
			"text": "Vive a Everafter da sempre.",
			"tick": 0,
		})
		records.append(record)
	_seed_relationships(records)
	return records


## Seeds a deterministic, symmetric relationship web. The social system is not
## implemented in this phase: these entries are data for a later one, and the
## test suite only checks that they point at existing inhabitants.
static func _seed_relationships(records: Array[NpcRecord]) -> void:
	for first_index in records.size():
		for second_index in range(first_index + 1, records.size()):
			var roll := (first_index + 1) * 37 + (second_index + 1) * 61
			var kind := ""
			var affinity := 0
			var familiarity := 0
			if roll % 11 == 0:
				kind = "familiare"
				affinity = 68
				familiarity = 85
			elif roll % 5 == 0:
				kind = "amico"
				affinity = 46
				familiarity = 58
			elif roll % 3 == 0:
				kind = "conoscente"
				affinity = 18
				familiarity = 27
			if kind.is_empty():
				continue
			_link(records[first_index], records[second_index], kind, affinity, familiarity)
	# Nobody starts completely isolated, even in a smaller population.
	for index in records.size():
		var record := records[index]
		if record.relationships.is_empty() and records.size() > 1:
			var other := records[(index + 1) % records.size()]
			_link(record, other, "vicino di casa", 22, 30)
			_link(other, record, "vicino di casa", 22, 30)
	# One memory that refers to an existing relationship, for every inhabitant.
	for index in records.size():
		var record := records[index]
		if record.relationships.is_empty():
			continue
		var other_id := String(record.relationships.keys()[index % record.relationships.size()])
		var other := _find_by_id(records, other_id)
		if other == null:
			continue
		var relation: Dictionary = record.relationships[other_id]
		record.memories.append({
			"kind": "relationship",
			"text": "Ricorda %s, %s del villaggio." % [other.display_name, relation["kind"]],
			"tick": 0,
		})


static func _link(
	first: NpcRecord, second: NpcRecord, kind: String, affinity: int, familiarity: int
) -> void:
	first.relationships[second.id] = {
		"kind": kind,
		"affinity": affinity,
		"familiarity": familiarity,
		"last_interaction_tick": 0,
	}
	second.relationships[first.id] = {
		"kind": kind,
		"affinity": affinity,
		"familiarity": familiarity,
		"last_interaction_tick": 0,
	}


static func _find_by_id(records: Array[NpcRecord], npc_id: String) -> NpcRecord:
	for record in records:
		if record.id == npc_id:
			return record
	return null
