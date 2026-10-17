class_name NpcPlace
extends RefCounted
## A named place in the simulated world, as pure data.
##
## A place is a logical destination ("the inn", "the fields", "home 3"), not a
## node. It knows where it is on the world XZ plane, whether it serves food and
## during which minutes it is open. The simulation only reads this data; the
## 3D side is free to choose how (or whether) to represent it.
##
## Open hours use minutes since midnight. `open_from == open_to` means "always
## open"; a range that wraps midnight (for example 22:00..02:00) is supported
## by [method is_open] as well.

enum Kind {
	HOME = 0,
	WORK = 1,
	FOOD = 2,
	REST = 3,
	SOCIAL = 4,
	LEISURE = 5,
}

const ALWAYS_OPEN_FROM := 0
const ALWAYS_OPEN_TO := 0

var id: String = ""
var display_name: String = ""
var kind: int = Kind.LEISURE
var position := Vector2.ZERO
var open_from_minute: int = ALWAYS_OPEN_FROM
var open_to_minute: int = ALWAYS_OPEN_TO
## True when an NPC can satisfy hunger here. Availability still depends on
## [method is_open]: the inn only serves food while it is open.
var serves_food: bool = false
## Soft capacity, reserved for the future social system. Not enforced yet.
var capacity: int = 0


func _init(
	initial_id: String = "",
	initial_display_name: String = "",
	initial_kind: int = Kind.LEISURE,
	initial_position: Vector2 = Vector2.ZERO,
	initial_open_from: int = ALWAYS_OPEN_FROM,
	initial_open_to: int = ALWAYS_OPEN_TO,
	initial_serves_food: bool = false,
	initial_capacity: int = 0
) -> void:
	id = initial_id
	display_name = initial_display_name
	kind = initial_kind
	position = initial_position
	open_from_minute = posmod(initial_open_from, SimulationClock.MINUTES_PER_DAY)
	open_to_minute = posmod(initial_open_to, SimulationClock.MINUTES_PER_DAY)
	serves_food = initial_serves_food
	capacity = maxi(initial_capacity, 0)


## True when the place is available at [param minute_of_day] (0..1439).
func is_open(minute_of_day: int) -> bool:
	if open_from_minute == open_to_minute:
		return true
	var minute := posmod(minute_of_day, SimulationClock.MINUTES_PER_DAY)
	if open_from_minute < open_to_minute:
		return minute >= open_from_minute and minute < open_to_minute
	# Wraps midnight, for example 22:00..02:00.
	return minute >= open_from_minute or minute < open_to_minute


## True when this place can feed an NPC right now.
func is_food_available(minute_of_day: int) -> bool:
	return serves_food and is_open(minute_of_day)


## True when this place is a plausible place to sleep or rest.
func is_rest_place() -> bool:
	return kind == Kind.HOME or kind == Kind.REST


## True when people may gather here during free time.
func is_social_place() -> bool:
	return kind == Kind.SOCIAL or kind == Kind.FOOD or kind == Kind.LEISURE


func kind_label() -> String:
	match kind:
		Kind.HOME:
			return "casa"
		Kind.WORK:
			return "lavoro"
		Kind.FOOD:
			return "cibo"
		Kind.REST:
			return "riposo"
		Kind.SOCIAL:
			return "ritrovo"
		_:
			return "svago"


func _to_string() -> String:
	return "%s (%s at %s)" % [id, display_name, position]
