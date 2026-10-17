class_name ChronicleWatcher
extends RefCounted
## Lightweight observer that translates system state changes into
## [ChronicleEntry] records.
##
## The watcher runs after simulation steps and compares snapshots of key
## system metrics (production surges, food shortage onsets/ends, project
## funding, important social events). It owns no simulation state of its
## own: it reads from the NPC, economy and social systems and writes to the
## [ChronicleBook].
##
## The watcher is NOT a SimulationSystem itself: it is called explicitly by
## whoever owns the clock cadence (the Game autoload once per frame, and the
## OfflineCatchup every batch during catch-up). This is what prevents
## double-counting during bulk advances.

const TAG := "Chronicle"

const NOTABLE_DAILY_PRODUCTION := 18
const FOOD_SHORTAGE_THRESHOLD := 4
const MAJOR_RELATIONSHIP_SHIFT := 20

var _book: ChronicleBook = null
var _npc_system: NpcSimulationSystem = null
var _economy: EconomySystem = null
var _social: SocialSystem = null

var _prev_food: int = -1
var _prev_wood: int = -1
var _prev_stone: int = -1
var _was_food_short: bool = false
var _was_wood_short: bool = false
var _was_stone_short: bool = false
var _prev_day: int = 1
var _seen_projects: Dictionary = {}
## Highest social event numeric id already promoted to the chronicle. Using
## an id watermark (instead of comparing tick numbers) makes bulk catch-up
## reliable: every new event is noticed even when we skip over ticks in
## batches.
var _last_seen_social_event_id: int = 0
var _initialized: bool = false


func _init(
	book: ChronicleBook,
	npc_system: NpcSimulationSystem,
	economy: EconomySystem,
	social: SocialSystem
) -> void:
	_book = book
	_npc_system = npc_system
	_economy = economy
	_social = social


func initialize(clock: SimulationClock) -> void:
	if _initialized:
		return
	_initialized = true
	if _economy != null:
		_prev_food = _economy.get_village_resource(ResourceType.FOOD)
		_prev_wood = _economy.get_village_resource(ResourceType.WOOD)
		_prev_stone = _economy.get_village_resource(ResourceType.STONE)
		_was_food_short = _prev_food <= FOOD_SHORTAGE_THRESHOLD
		_was_wood_short = _prev_wood < ResourceType.shortage_threshold(ResourceType.WOOD)
		_was_stone_short = _prev_stone < ResourceType.shortage_threshold(ResourceType.STONE)
	_prev_day = clock.get_display_day()
	_seed_initial_projects()
	_seed_initial_social_watermark()
	_book.record(
		ChronicleEntry.Category.MILESTONE,
		clock.get_display_day(),
		clock.get_minute_of_day(),
		clock.tick,
		40,
		"Il villaggio di Everafter si risveglia: la giornata ha inizio.",
		[],
		[],
		{"kind": "world_start"}
	)


## Observe the current clock/systems state and record any transitions that
## happened since the last call.
func observe(tick: int, clock: SimulationClock) -> void:
	if _book == null:
		return
	_check_economy(tick, clock)
	_check_day_change(tick, clock)
	_check_social_events(tick, clock)


func to_dict() -> Dictionary:
	return {
		"prev_food": _prev_food,
		"prev_wood": _prev_wood,
		"prev_stone": _prev_stone,
		"was_food_short": _was_food_short,
		"was_wood_short": _was_wood_short,
		"was_stone_short": _was_stone_short,
		"prev_day": _prev_day,
		"seen_projects": _seen_projects.duplicate(true),
		"last_seen_social_event_id": _last_seen_social_event_id,
	}


func from_dict(data: Dictionary) -> void:
	_initialized = true
	_prev_food = int(data.get("prev_food", -1))
	_prev_wood = int(data.get("prev_wood", -1))
	_prev_stone = int(data.get("prev_stone", -1))
	_was_food_short = bool(data.get("was_food_short", false))
	_was_wood_short = bool(data.get("was_wood_short", false))
	_was_stone_short = bool(data.get("was_stone_short", false))
	_prev_day = int(data.get("prev_day", 1))
	_seen_projects = (data.get("seen_projects", {}) as Dictionary).duplicate(true)
	_last_seen_social_event_id = int(data.get("last_seen_social_event_id", 0))


# --- internals ---------------------------------------------------------------


func _seed_initial_projects() -> void:
	if _economy == null:
		return
	for pid in _economy.completed_projects:
		_seen_projects[pid] = true


func _seed_initial_social_watermark() -> void:
	if _social == null:
		return
	var highest := 0
	for event in _social.events:
		highest = maxi(highest, _parse_event_tail(event.id))
	_last_seen_social_event_id = highest


func _check_economy(tick: int, clock: SimulationClock) -> void:
	if _economy == null:
		return
	# Project completions.
	for pid in _economy.completed_projects:
		if not _seen_projects.has(pid):
			_seen_projects[pid] = true
			var label := _project_label(pid)
			_book.record(
				ChronicleEntry.Category.PROJECT,
				clock.get_display_day(),
				clock.get_minute_of_day(),
				tick,
				55,
				"Progetto comunitario completato: %s." % label,
				[],
				[ResourceType.WOOD, ResourceType.STONE, ResourceType.COIN],
				{"kind": "project_completed", "project_id": pid}
			)
	var food := _economy.get_village_resource(ResourceType.FOOD)
	var wood := _economy.get_village_resource(ResourceType.WOOD)
	var stone := _economy.get_village_resource(ResourceType.STONE)

	if not _was_food_short and food <= FOOD_SHORTAGE_THRESHOLD:
		_was_food_short = true
		_book.record(
			ChronicleEntry.Category.SHORTAGE,
			clock.get_display_day(),
			clock.get_minute_of_day(),
			tick,
			70,
			"Le scorte di cibo scendono a %d: il villaggio rischia la fame." % food,
			[],
			[ResourceType.FOOD],
			{"resource": ResourceType.FOOD, "amount": food, "kind": "shortage_start"}
		)
	elif _was_food_short and food > FOOD_SHORTAGE_THRESHOLD + 4:
		_was_food_short = false
		_book.record(
			ChronicleEntry.Category.PRODUCTION,
			clock.get_display_day(),
			clock.get_minute_of_day(),
			tick,
			45,
			"Le scorte di cibo sono tornate a %d: la crisi è rientrata." % food,
			[],
			[ResourceType.FOOD],
			{"resource": ResourceType.FOOD, "amount": food, "kind": "shortage_end"}
		)

	if not _was_wood_short and wood < ResourceType.shortage_threshold(ResourceType.WOOD):
		_was_wood_short = true
		_book.record(
			ChronicleEntry.Category.SHORTAGE,
			clock.get_display_day(),
			clock.get_minute_of_day(),
			tick,
			50,
			"Il legno scarseggia (%d unità): i progetti comunitari sono a rischio." % wood,
			[],
			[ResourceType.WOOD],
			{"resource": ResourceType.WOOD, "amount": wood, "kind": "shortage_start"}
		)
	elif _was_wood_short and wood >= ResourceType.shortage_threshold(ResourceType.WOOD) + 2:
		_was_wood_short = false
		_book.record(
			ChronicleEntry.Category.PRODUCTION,
			clock.get_display_day(),
			clock.get_minute_of_day(),
			tick,
			30,
			"Le scorte di legno sono tornate a %d unità." % wood,
			[],
			[ResourceType.WOOD],
			{"resource": ResourceType.WOOD, "amount": wood, "kind": "shortage_end"}
		)

	if not _was_stone_short and stone < ResourceType.shortage_threshold(ResourceType.STONE):
		_was_stone_short = true
		_book.record(
			ChronicleEntry.Category.SHORTAGE,
			clock.get_display_day(),
			clock.get_minute_of_day(),
			tick,
			50,
			"La pietra scarseggia (%d unità): le costruzioni rallentano." % stone,
			[],
			[ResourceType.STONE],
			{"resource": ResourceType.STONE, "amount": stone, "kind": "shortage_start"}
		)
	elif _was_stone_short and stone >= ResourceType.shortage_threshold(ResourceType.STONE) + 2:
		_was_stone_short = false
		_book.record(
			ChronicleEntry.Category.PRODUCTION,
			clock.get_display_day(),
			clock.get_minute_of_day(),
			tick,
			30,
			"Le scorte di pietra sono tornate a %d unità." % stone,
			[],
			[ResourceType.STONE],
			{"resource": ResourceType.STONE, "amount": stone, "kind": "shortage_end"}
		)

	_prev_food = food
	_prev_wood = wood
	_prev_stone = stone


func _check_day_change(tick: int, clock: SimulationClock) -> void:
	var day := clock.get_display_day()
	if day == _prev_day:
		return
	_book.record(
		ChronicleEntry.Category.MILESTONE,
		day,
		clock.get_minute_of_day(),
		tick,
		25,
		"Giorno %d: il sole sorge sul villaggio." % day,
		[],
		[],
		{"kind": "day_start", "day": day}
	)
	_prev_day = day


func _check_social_events(_tick: int, _clock: SimulationClock) -> void:
	if _social == null:
		return
	for event in _social.events:
		var eid := _parse_event_tail(event.id)
		if eid <= 0 or eid <= _last_seen_social_event_id:
			continue
		if event.importance < 45:
			_last_seen_social_event_id = maxi(_last_seen_social_event_id, eid)
			continue
		var cat := ChronicleEntry.Category.RELATIONSHIP
		var imp := clampi(event.importance, 8, 90)
		match event.kind:
			SocialEvent.Kind.HELP:
				cat = ChronicleEntry.Category.HELP
				imp = maxi(imp, 55)
			SocialEvent.Kind.DISAGREEMENT:
				cat = ChronicleEntry.Category.RELATIONSHIP
				imp = maxi(imp, 50)
			SocialEvent.Kind.COOPERATION:
				cat = ChronicleEntry.Category.RELATIONSHIP
		_book.record(
			cat,
			event.day,
			event.minute_of_day,
			event.tick,
			imp,
			event.summary,
			event.actor_ids,
			[],
			{"social_event_id": event.id, "kind": "social_event",
			 "outcome": event.outcome}
		)
		_last_seen_social_event_id = maxi(_last_seen_social_event_id, eid)


## Extracts the numeric tail of a social event id like "evt_000042".
static func _parse_event_tail(event_id: String) -> int:
	if not event_id.begins_with("evt_"):
		return 0
	var tail := event_id.trim_prefix("evt_")
	return int(tail) if tail.is_valid_int() else 0


static func _project_label(project_id: String) -> String:
	match project_id:
		"granary_repair":
			return "Rinforzo del Granaio Comune"
		"logging_trestle":
			return "Cavalletto e Tettoia della Segheria"
		"quarry_shoring":
			return "Armatura del Banco di Pietra"
		"well_maintenance":
			return "Manutenzione del Pozzo e della Piazza"
	return project_id
