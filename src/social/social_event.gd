class_name SocialEvent
extends RefCounted
## A structured record of something that happened between inhabitants.
##
## This is the **objective** side of the social layer: what the world agrees
## happened, with the ids of everybody involved, the simulated day, the place
## and the changes it produced. Individual memories (`NpcMemory`) are the
## *subjective* side and always point back here through [member id].
##
## Keeping the two apart is deliberate. A memory can be incomplete, biased or
## forgotten; the event cannot. When the chronicle phase arrives it will read
## these events, and an inhabitant's version of a story will still be readable
## as *their* version rather than as the truth.
##
## An event is immutable once produced: nothing in the simulation edits a past
## event, it only appends new ones.

enum Kind {
	GREETING = 0,
	CONVERSATION = 1,
	COOPERATION = 2,
	HELP = 3,
	DISAGREEMENT = 4,
}

enum Outcome {
	NEUTRAL = 0,
	POSITIVE = 1,
	REFUSED = 2,
	NEGATIVE = 3,
}

const IMPORTANCE_MIN := 0
const IMPORTANCE_MAX := 100

## Stable id inside this world ("evt_000042"), assigned by `SocialSystem`.
var id: String = ""
var kind: int = Kind.GREETING
var outcome: int = Outcome.NEUTRAL

## When it happened, in simulated time.
var tick: int = 0
var day: int = 1
var minute_of_day: int = 0

## Where it happened.
var place_id: String = ""
var place_name: String = ""

## Everybody involved, in canonical (sorted id) order. Never empty for a real
## event: an interaction without participants is not an event.
var actor_ids: PackedStringArray = PackedStringArray()
## Who started it, when it makes a difference (help, cooperation).
var initiator_id: String = ""

## Short human readable description, built from a template by `SocialRules`.
var summary: String = ""
## 0..100. Drives memory retention and the future chronicle.
var importance: int = 0
## The changes this event actually applied, as `name -> value`. Kept so the UI
## can answer "why did this number change?" without guessing.
var effects: Dictionary = {}


func involves(npc_id: String) -> bool:
	for actor_id in actor_ids:
		if actor_id == npc_id:
			return true
	return false


func actor_count() -> int:
	return actor_ids.size()


## True when the event is worth keeping in the objective log and in memories.
func is_significant(minimum_importance: int) -> bool:
	return importance >= maxi(minimum_importance, IMPORTANCE_MIN)


func kind_label() -> String:
	match kind:
		Kind.GREETING:
			return "saluto"
		Kind.CONVERSATION:
			return "conversazione"
		Kind.COOPERATION:
			return "cooperazione"
		Kind.HELP:
			return "aiuto"
		Kind.DISAGREEMENT:
			return "disaccordo"
	return "incontro"


func outcome_label() -> String:
	match outcome:
		Outcome.POSITIVE:
			return "positivo"
		Outcome.REFUSED:
			return "rifiutato"
		Outcome.NEGATIVE:
			return "negativo"
	return "neutro"


## Reads the actor ids through [param names] (`id -> display name`). Unknown ids
## are shown as they are, so a broken reference stays visible instead of
## turning into an empty sentence.
func actors_text(names: Dictionary) -> String:
	var parts: PackedStringArray = []
	for actor_id in actor_ids:
		parts.append(String(names.get(actor_id, actor_id)))
	return ", ".join(parts) if not parts.is_empty() else "—"


func is_valid() -> bool:
	return (
		not id.is_empty()
		and actor_ids.size() >= 2
		and importance >= IMPORTANCE_MIN
		and importance <= IMPORTANCE_MAX
		and day >= 1
		and minute_of_day >= 0
		and minute_of_day < SimulationClock.MINUTES_PER_DAY
	)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"outcome": outcome,
		"tick": tick,
		"day": day,
		"minute_of_day": minute_of_day,
		"place_id": place_id,
		"place_name": place_name,
		"actor_ids": actor_ids.duplicate(),
		"initiator_id": initiator_id,
		"summary": summary,
		"importance": importance,
		"effects": effects.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	id = String(data.get("id", id))
	kind = int(data.get("kind", kind))
	outcome = int(data.get("outcome", outcome))
	tick = int(data.get("tick", tick))
	day = int(data.get("day", day))
	minute_of_day = int(data.get("minute_of_day", minute_of_day))
	place_id = String(data.get("place_id", place_id))
	place_name = String(data.get("place_name", place_name))
	actor_ids = PackedStringArray()
	for actor_id in data.get("actor_ids", []):
		actor_ids.append(String(actor_id))
	initiator_id = String(data.get("initiator_id", initiator_id))
	summary = String(data.get("summary", summary))
	importance = clampi(
		int(data.get("importance", importance)), IMPORTANCE_MIN, IMPORTANCE_MAX
	)
	effects = (data.get("effects", {}) as Dictionary).duplicate(true)


func _to_string() -> String:
	return "giorno %d %s — %s" % [day, SimulationClock.format_minutes(minute_of_day), summary]
