class_name NpcMemory
extends RefCounted
## One memory held by one inhabitant.
##
## A memory is **not** the event. It is what a character kept of it: whose head
## it is in ([member owner_id]), how important it felt to them
## ([member importance]), how sure they are ([member certainty]) and a short
## description written from their point of view ([member summary]). The event
## itself lives in `SocialEvent`, and [member event_id] points at it, so the two
## can always be compared: a memory may one day be incomplete or wrong while the
## event stays exact. That separation is what lets a future phase give an
## inhabitant a genuinely partial view of something they only half saw.
##
## In this phase every memory is `SOURCE_DIRECT` (the character was there) and
## `certainty` is `CERTAINTY_WITNESSED`. The fields exist now so that "I heard
## it from somebody else" is a data change later, not a schema change.
##
## Nothing here is a node, a resource or a scene: memories are plain values that
## a save file can carry.

enum Kind {
	ORIGIN = 0,
	GREETING = 1,
	CONVERSATION = 2,
	COOPERATION = 3,
	HELP = 4,
	DISAGREEMENT = 5,
}

const IMPORTANCE_MIN := 0
const IMPORTANCE_MAX := 100
## Memories at or above this importance are only dropped when the capacity
## leaves no other choice, and the eviction is counted and logged.
const PERMANENT_IMPORTANCE := 75
## Days during which a memory counts as recent for the retention score.
const RECENT_WINDOW_DAYS := 6
const SOURCE_DIRECT := "diretto"
const SOURCE_REPORTED := "raccontato"
const CERTAINTY_WITNESSED := 100

## Which side of the interaction the owner was on. This is what makes "they
## helped me" and "I helped them" two different memories of the same event.
const ROLE_SHARED := "condiviso"
const ROLE_RECEIVED := "ricevuto"
const ROLE_GIVEN := "offerto"
const ROLE_STARTED := "iniziato"
const ROLE_DECLINED := "rifiutato"

## Unique inside the world ("mem_000107"), assigned by `MemoryBook`.
var id: String = ""
## Whose memory this is. The same event produces one memory per participant,
## each with its own id and its own importance.
var owner_id: String = ""
var kind: int = Kind.ORIGIN
## Reference to the objective event, empty for memories that predate the
## simulation (the starting background of a character).
var event_id: String = ""

var tick: int = 0
var day: int = 1
## The other inhabitants the memory involves. The owner is *not* listed here:
## [member owner_id] already says whose memory this is, and [method involves]
## checks both.
var other_ids: PackedStringArray = PackedStringArray()
var place_id: String = ""
var outcome: int = SocialEvent.Outcome.NEUTRAL
## The owner's side of the interaction (`ROLE_*`), empty when it does not apply.
var role: String = ""

## Short description from the owner's point of view.
var summary: String = ""
## 0..100: how much this matters *to the owner*. Drives retention.
var importance: int = 0
## How the owner knows it. Only [constant SOURCE_DIRECT] is produced today.
var source: String = SOURCE_DIRECT
## 0..100. A witness is certain; a rumour is not. Reserved for a later phase.
var certainty: int = CERTAINTY_WITNESSED


func involves(npc_id: String) -> bool:
	if npc_id == owner_id:
		return true
	for other_id in other_ids:
		if other_id == npc_id:
			return true
	return false


## Whole days elapsed since the memory was formed. Never negative, even if a
## save file carries a day in the future.
func age_in_days(current_day: int) -> int:
	return maxi(current_day - day, 0)


## Why this memory survives longer than another one:
## `importance * 3 + 2 points per day of recency`, capped by the recency
## window. Importance dominates by design — being recent only breaks ties
## between memories of comparable weight — so a single important event outlives
## a dozen small talk exchanges.
func retention_score(current_day: int) -> int:
	var recency := maxi(RECENT_WINDOW_DAYS - age_in_days(current_day), 0)
	return importance * 3 + recency * 2


## True when dropping this memory needs an explicit reason.
func is_protected() -> bool:
	return importance >= PERMANENT_IMPORTANCE


func kind_label() -> String:
	var label := "ricordo"
	match kind:
		Kind.ORIGIN:
			label = "ricordo d'origine"
		Kind.GREETING:
			label = "saluto"
		Kind.CONVERSATION:
			label = "conversazione"
		Kind.COOPERATION:
			label = "cooperazione"
		Kind.HELP:
			label = "aiuto"
		Kind.DISAGREEMENT:
			label = "disaccordo"
	return label


func is_valid() -> bool:
	return (
		not id.is_empty()
		and not owner_id.is_empty()
		and importance >= IMPORTANCE_MIN
		and importance <= IMPORTANCE_MAX
		and certainty >= 0
		and certainty <= 100
		and day >= 1
		and not summary.is_empty()
	)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"owner_id": owner_id,
		"kind": kind,
		"event_id": event_id,
		"tick": tick,
		"day": day,
		"other_ids": other_ids.duplicate(),
		"place_id": place_id,
		"outcome": outcome,
		"role": role,
		"summary": summary,
		"importance": importance,
		"source": source,
		"certainty": certainty,
	}


func from_dict(data: Dictionary) -> void:
	id = String(data.get("id", id))
	owner_id = String(data.get("owner_id", owner_id))
	kind = int(data.get("kind", kind))
	event_id = String(data.get("event_id", event_id))
	tick = int(data.get("tick", tick))
	day = int(data.get("day", day))
	other_ids = PackedStringArray()
	for other_id in data.get("other_ids", []):
		other_ids.append(String(other_id))
	place_id = String(data.get("place_id", place_id))
	outcome = int(data.get("outcome", outcome))
	role = String(data.get("role", role))
	summary = String(data.get("summary", summary))
	importance = clampi(int(data.get("importance", importance)), IMPORTANCE_MIN, IMPORTANCE_MAX)
	source = String(data.get("source", source))
	certainty = clampi(int(data.get("certainty", certainty)), 0, 100)


func _to_string() -> String:
	return "giorno %d — %s (importanza %d)" % [day, summary, importance]
