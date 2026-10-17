class_name NpcPlaceRegistry
extends RefCounted
## The set of places the NPC simulation can talk about.
##
## Pure data, exactly like `NpcPlace`: no nodes, no meshes, no navigation. The
## world builds an instance from its layout and injects it into the simulation;
## tests build a tiny synthetic one. IDs are unique and [method add_place]
## refuses duplicates instead of silently shadowing a place.

var _places: Array[NpcPlace] = []
var _by_id: Dictionary = {}


## Registers a place. Returns false (and pushes an error) if the ID is already
## taken, so a typo in a data table cannot make two destinations collapse.
func add_place(place: NpcPlace) -> bool:
	if place == null:
		return false
	if place.id.is_empty():
		push_error("NpcPlaceRegistry: a place needs a non-empty id.")
		return false
	if _by_id.has(place.id):
		push_error("NpcPlaceRegistry: duplicate place id '%s'." % place.id)
		return false
	_places.append(place)
	_by_id[place.id] = place
	return true


## Convenience constructor used by the world and by the tests.
func add(
	place_id: String,
	display_name: String,
	kind: int,
	position: Vector2,
	open_from: int = NpcPlace.ALWAYS_OPEN_FROM,
	open_to: int = NpcPlace.ALWAYS_OPEN_TO,
	serves_food: bool = false,
	capacity: int = 0
) -> NpcPlace:
	var place := NpcPlace.new(
		place_id, display_name, kind, position, open_from, open_to, serves_food, capacity
	)
	if not add_place(place):
		return null
	return place


func get_place(place_id: String) -> NpcPlace:
	return _by_id.get(place_id, null) as NpcPlace


func has_place(place_id: String) -> bool:
	return _by_id.has(place_id)


func get_count() -> int:
	return _places.size()


func all_places() -> Array[NpcPlace]:
	return _places.duplicate()


func get_place_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for place in _places:
		ids.append(place.id)
	return ids


func places_of_kind(kind: int) -> Array[NpcPlace]:
	var result: Array[NpcPlace] = []
	for place in _places:
		if place.kind == kind:
			result.append(place)
	return result


## Homes in registration order. The simulation assigns them to NPCs by index.
func home_places() -> Array[NpcPlace]:
	return places_of_kind(NpcPlace.Kind.HOME)


## First open food place. [param preferred_id] wins when it is open, which lets
## an NPC go back to its usual inn instead of the first one in the list.
func find_food_place(minute_of_day: int, preferred_id: String = "") -> NpcPlace:
	var preferred := get_place(preferred_id)
	if preferred != null and preferred.is_food_available(minute_of_day):
		return preferred
	# Public kitchens first, so the inn and the market are actually used even
	# though every home is registered as a pantry before them.
	for place in _places:
		if place.kind == NpcPlace.Kind.FOOD and place.is_food_available(minute_of_day):
			return place
	for place in _places:
		if place.kind == NpcPlace.Kind.HOME and place.is_food_available(minute_of_day):
			return place
	return null


## First open social place, honouring the preferred one when possible.
func find_social_place(minute_of_day: int, preferred_id: String = "") -> NpcPlace:
	var preferred := get_place(preferred_id)
	if preferred != null and preferred.is_social_place() and preferred.is_open(minute_of_day):
		return preferred
	for place in _places:
		if place.is_social_place() and place.is_open(minute_of_day):
			return place
	return null


## First open rest place, honouring the preferred one when possible.
func find_rest_place(minute_of_day: int, preferred_id: String = "") -> NpcPlace:
	var preferred := get_place(preferred_id)
	if preferred != null and preferred.is_rest_place() and preferred.is_open(minute_of_day):
		return preferred
	for place in _places:
		if place.is_rest_place() and place.is_open(minute_of_day):
			return place
	return null


## "Best place of this kind that is open now", with a deterministic fallback to
## the first place of that kind even when all are closed. Used for leisure and
## for diagnostics, not for food (which must genuinely be available).
func find_open_place(kind: int, minute_of_day: int, preferred_id: String = "") -> NpcPlace:
	var preferred := get_place(preferred_id)
	if preferred != null and preferred.kind == kind and preferred.is_open(minute_of_day):
		return preferred
	for place in _places:
		if place.kind == kind and place.is_open(minute_of_day):
			return place
	return null


## Returns human readable problems. An empty array means the registry is usable.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	var seen: Dictionary = {}
	for place in _places:
		if place.id.is_empty():
			problems.append("a place has an empty id")
		elif seen.has(place.id):
			problems.append("duplicate place id '%s'" % place.id)
		seen[place.id] = true
		if not place.position.is_finite():
			problems.append("place '%s' has a non-finite position" % place.id)
	return problems
