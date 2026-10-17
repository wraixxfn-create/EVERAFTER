class_name NpcRecord
extends RefCounted
## Everything the simulation knows about one inhabitant, and nothing about how
## that inhabitant is drawn.
##
## The record is a `RefCounted` value object: no node, no mesh, no camera. This
## is deliberate. A record keeps being simulated while its 3D representation is
## culled, not instanced yet or simply not visible, and a headless test can
## advance a hundred of them without a scene tree.
##
## Goals and activities are separate on purpose:
## * [member goal] is the *intention* ("go to work", "find food");
## * [member activity] is what the body is doing right now ("walking").
## Keeping both lets the UI explain a character instead of only showing an enum.

enum Goal {
	IDLE = 0,
	GO_TO_WORK = 1,
	WORK = 2,
	SEEK_FOOD = 3,
	EAT = 4,
	SLEEP = 5,
	GO_HOME = 6,
	REST = 7,
	SOCIALIZE = 8,
	WANDER = 9,
	BLOCKED = 10,
}

enum Activity {
	IDLE = 0,
	WALKING = 1,
	WORKING = 2,
	SLEEPING = 3,
	RESTING = 4,
	EATING = 5,
	SOCIALIZING = 6,
	BLOCKED = 7,
}

# Identity.
var id: String = ""
var display_name: String = ""
var age: int = 30
var profession_id: String = ""
var profession_label: String = ""
var profession_color := Color(0.72, 0.68, 0.6, 1.0)
var personality := NpcPersonality.new()
var needs := NpcNeeds.new()

# Work.
var home_place_id: String = ""
var work_place_id: String = ""
var work_start_minute: int = 8 * 60
var work_end_minute: int = 16 * 60

# Space. XZ only: the terrain decides Y, in the presentation layer.
var position := Vector2.ZERO
var destination := Vector2.ZERO
var current_place_id: String = ""
var current_place_name: String = ""
var destination_place_id: String = ""
var destination_place_name: String = ""
var has_destination: bool = false
var path := PackedVector2Array()
var path_index: int = 0

# State.
var goal: int = Goal.IDLE
var activity: int = Activity.IDLE
var action_ticks_left: int = 0
var goal_reason: String = ""
var last_activity_change_tick: int = 0
var blocked_ticks: int = 0
## Used to rotate between free-time destinations without randomness.
var leisure_cursor: int = 0
## True when the last meal consumed a real food ration from the economy.
var last_meal_satisfied: bool = true

## One line of personal background, written by the roster. The social layer
## turns it into the character's first memory (`NpcMemory.Kind.ORIGIN`); the
## record itself stores no relationships and no memories, because that state has
## a single owner: `RelationshipGraph` and `MemoryBook` in `src/social/`.
var origin_note: String = ""


## True when [param minute_of_day] falls inside this NPC's work window.
func is_within_work_hours(minute_of_day: int) -> bool:
	return minute_of_day >= work_start_minute and minute_of_day < work_end_minute


func set_activity(new_activity: int, tick: int) -> void:
	if activity == new_activity:
		return
	activity = new_activity
	last_activity_change_tick = tick


func set_goal(new_goal: int, reason: String = "") -> void:
	goal = new_goal
	goal_reason = reason
	action_ticks_left = 0


func goal_label() -> String:
	var label := "Decidere cosa fare"
	match goal:
		Goal.GO_TO_WORK:
			label = "Raggiungere il posto di lavoro"
		Goal.WORK:
			label = "Lavorare fino alle %s" % SimulationClock.format_minutes(work_end_minute)
		Goal.SEEK_FOOD:
			label = "Trovare qualcosa da mangiare"
		Goal.EAT:
			label = "Mangiare"
		Goal.SLEEP:
			label = "Dormire fino al mattino"
		Goal.GO_HOME:
			label = "Tornare a casa"
		Goal.REST:
			label = "Recuperare energie"
		Goal.SOCIALIZE:
			label = "Passare del tempo con gli altri"
		Goal.WANDER:
			label = "Passeggiare"
		Goal.BLOCKED:
			label = "Riprendersi da un percorso bloccato"
	return label


func activity_label() -> String:
	var label := "In attesa"
	match activity:
		Activity.WALKING:
			label = "In cammino"
			if not destination_place_name.is_empty():
				label = "In cammino verso %s" % destination_place_name
		Activity.WORKING:
			label = "Al lavoro come %s" % profession_label.to_lower()
		Activity.SLEEPING:
			label = "Dorme"
		Activity.RESTING:
			label = "Si riposa"
		Activity.EATING:
			label = "Sta mangiando"
		Activity.SOCIALIZING:
			label = "Socializza"
		Activity.BLOCKED:
			label = "Bloccato: destinazione irraggiungibile"
	return label


func mood_label() -> String:
	if needs.wellbeing >= 75.0:
		return "sereno"
	if needs.wellbeing >= 50.0:
		return "tranquillo"
	if needs.wellbeing >= 25.0:
		return "inquieto"
	return "provato"


## Short, human readable state summary shown by the observation panel.
func summary_text() -> String:
	var where := "in cammino"
	if activity != Activity.WALKING:
		if not current_place_name.is_empty():
			where = "a %s" % current_place_name
		else:
			where = "nel villaggio"
	return "%s, %d anni, %s. %s; si trova %s. Energia %d, fame %d, benessere %d." % [
		display_name,
		age,
		profession_label.to_lower(),
		activity_label(),
		where,
		int(round(needs.energy)),
		int(round(needs.hunger)),
		int(round(needs.wellbeing)),
	]


## Snapshot for the future persistence module. The returned dictionary is a
## copy: an external reader cannot mutate the live record through it.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"age": age,
		"profession_id": profession_id,
		"profession_label": profession_label,
		"profession_color": profession_color,
		"personality": personality.to_dict(),
		"needs": needs.to_dict(),
		"home_place_id": home_place_id,
		"work_place_id": work_place_id,
		"work_start_minute": work_start_minute,
		"work_end_minute": work_end_minute,
		"position": position,
		"destination": destination,
		"current_place_id": current_place_id,
		"current_place_name": current_place_name,
		"destination_place_id": destination_place_id,
		"destination_place_name": destination_place_name,
		"has_destination": has_destination,
		"path": path.duplicate(),
		"path_index": path_index,
		"goal": goal,
		"activity": activity,
		"action_ticks_left": action_ticks_left,
		"goal_reason": goal_reason,
		"last_activity_change_tick": last_activity_change_tick,
		"blocked_ticks": blocked_ticks,
		"leisure_cursor": leisure_cursor,
		"last_meal_satisfied": last_meal_satisfied,
		"origin_note": origin_note,
	}


func from_dict(data: Dictionary) -> void:
	id = String(data.get("id", id))
	display_name = String(data.get("display_name", display_name))
	age = int(data.get("age", age))
	profession_id = String(data.get("profession_id", profession_id))
	profession_label = String(data.get("profession_label", profession_label))
	profession_color = data.get("profession_color", profession_color)
	personality.from_dict(data.get("personality", {}))
	needs.from_dict(data.get("needs", {}))
	home_place_id = String(data.get("home_place_id", home_place_id))
	work_place_id = String(data.get("work_place_id", work_place_id))
	work_start_minute = int(data.get("work_start_minute", work_start_minute))
	work_end_minute = int(data.get("work_end_minute", work_end_minute))
	position = data.get("position", position)
	destination = data.get("destination", destination)
	current_place_id = String(data.get("current_place_id", current_place_id))
	current_place_name = String(data.get("current_place_name", current_place_name))
	destination_place_id = String(data.get("destination_place_id", destination_place_id))
	destination_place_name = String(data.get("destination_place_name", destination_place_name))
	has_destination = bool(data.get("has_destination", has_destination))
	path = data.get("path", PackedVector2Array())
	path_index = int(data.get("path_index", path_index))
	goal = int(data.get("goal", goal))
	activity = int(data.get("activity", activity))
	action_ticks_left = int(data.get("action_ticks_left", action_ticks_left))
	goal_reason = String(data.get("goal_reason", goal_reason))
	last_activity_change_tick = int(data.get("last_activity_change_tick", last_activity_change_tick))
	blocked_ticks = int(data.get("blocked_ticks", blocked_ticks))
	leisure_cursor = int(data.get("leisure_cursor", leisure_cursor))
	last_meal_satisfied = bool(data.get("last_meal_satisfied", last_meal_satisfied))
	origin_note = String(data.get("origin_note", origin_note))
	needs.clamp_all()
	personality.clamp_all()


func _to_string() -> String:
	return "%s (%s) — %s" % [display_name, profession_label, activity_label()]
