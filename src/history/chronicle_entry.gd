class_name ChronicleEntry
extends RefCounted
## One structured entry in the world chronicle.
##
## A chronicle entry is broader than a `SocialEvent`: it records production
## surges, food shortages, community projects, day transitions and important
## relationship changes. It is owned by `ChronicleBook`, never by a character,
## and it is the source of truth shown by the chronicle panel.
##
## An entry is immutable once created, like a social event.

enum Category {
	## Produzione eccezionale o buon raccolto.
	PRODUCTION = 0,
	## Scarsità di cibo, legno o pietra.
	SHORTAGE = 1,
	## Un aiuto concreto tra abitanti, anche quando non nasce da un'interazione
	## faccia a faccia (es. condivisione di cibo da parte del villaggio).
	HELP = 2,
	## Cambiamento importante in una relazione (nuova fiducia, litigio grave,
	## riconciliazione).
	RELATIONSHIP = 3,
	## Progetto comunitario finanziato o completato.
	PROJECT = 4,
	## Inizio di un nuovo giorno, stagione o pietra miliare.
	MILESTONE = 5,
	## Evento interno di sistema (caricamento, avanzamento offline).
	SYSTEM = 6,
}

const IMPORTANCE_MIN := 0
const IMPORTANCE_MAX := 100

## Stable id across saves ("chr_000042"), assigned by `ChronicleBook`.
var id: String = ""
## When the entry refers to, in simulated time.
var day: int = 1
var minute_of_day: int = 0
var tick: int = 0
var category: int = Category.MILESTONE
## Inhabitants, places or resources this entry is about. References are
## plain strings (ids), never live references, so that an entry survives
## save/load without pointers becoming stale.
var subject_ids: PackedStringArray = PackedStringArray()
var resource_ids: PackedStringArray = PackedStringArray()
## Human readable description in Italian, already final when appended.
var summary: String = ""
## 0..100, drives retention policies and display ordering.
var importance: int = 0
## Optional structured details (e.g. amounts produced, well-being change).
var details: Dictionary = {}


func category_label() -> String:
	match category:
		Category.PRODUCTION:
			return "Produzione"
		Category.SHORTAGE:
			return "Carenza"
		Category.HELP:
			return "Aiuto"
		Category.RELATIONSHIP:
			return "Relazione"
		Category.PROJECT:
			return "Progetto"
		Category.MILESTONE:
			return "Tappa"
		Category.SYSTEM:
			return "Sistema"
	return "Altro"


## True for entries that retention policies protect more aggressively.
func is_landmark() -> bool:
	return importance >= ChronicleBook.LANDMARK_IMPORTANCE


func is_valid() -> bool:
	return (
		not id.is_empty()
		and day >= 1
		and minute_of_day >= 0
		and minute_of_day < SimulationClock.MINUTES_PER_DAY
		and importance >= IMPORTANCE_MIN
		and importance <= IMPORTANCE_MAX
		and not summary.is_empty()
	)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"day": day,
		"minute_of_day": minute_of_day,
		"tick": tick,
		"category": category,
		"subject_ids": subject_ids.duplicate(),
		"resource_ids": resource_ids.duplicate(),
		"summary": summary,
		"importance": importance,
		"details": details.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	id = String(data.get("id", id))
	day = maxi(int(data.get("day", day)), 1)
	minute_of_day = clampi(
		int(data.get("minute_of_day", minute_of_day)), 0, SimulationClock.MINUTES_PER_DAY - 1
	)
	tick = maxi(int(data.get("tick", tick)), 0)
	category = int(data.get("category", category))
	subject_ids = PackedStringArray()
	for sid in data.get("subject_ids", []):
		subject_ids.append(String(sid))
	resource_ids = PackedStringArray()
	for rid in data.get("resource_ids", []):
		resource_ids.append(String(rid))
	summary = String(data.get("summary", summary))
	importance = clampi(
		int(data.get("importance", importance)), IMPORTANCE_MIN, IMPORTANCE_MAX
	)
	details = (data.get("details", {}) as Dictionary).duplicate(true)


func _to_string() -> String:
	return "giorno %d %s [%s] %s" % [
		day, SimulationClock.format_minutes(minute_of_day), category_label(), summary
	]
