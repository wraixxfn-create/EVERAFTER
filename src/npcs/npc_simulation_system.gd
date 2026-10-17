class_name NpcSimulationSystem
extends SimulationSystem
## The first autonomous inhabitant simulation.
##
## One simulated minute is one tick. Every tick this system updates **all**
## records, whether or not a single one of them is visible: it never touches a
## node, a camera or the scene tree. The 3D presenter and the UI only read the
## resulting records.
##
## Behaviour is a small, explicit rule machine, not a planner:
## * urgent hunger beats everything: look for an open place that serves food and
##   walk there (home is the last pantry);
## * during their own work window inhabitants go to their workplace and work;
## * between 22:00 and 06:00 they sleep at home, unless their shift is still
##   running;
## * otherwise ordinary needs decide between eating, resting and free time;
## * free time alternates deterministically between social places and a walk,
##   driven by personality and by a per-record cursor rather than by an RNG.
##
## Movement is continuous: [constant WALK_DISTANCE_PER_TICK] world units per
## tick along an [NpcRouteGraph] path, never a jump to the destination. A place
## the graph cannot reach is reported once and replaced by a safe alternative;
## the record enters a short [constant Activity.BLOCKED] state instead of
## pretending to move.
##
## Determinism: no RNG, no wall clock, no frame delta. The same initial records
## and the same number of ticks produce the same records on every machine.

const SYSTEM_NAME := "npc_life"
const TAG := "NPC"

## Gameplay-scaled walking pace, in world units per simulated minute. The whole
## day is compressed, so this is not a real-world speed: at x1 it reads as a
## walk across the village in a few real seconds.
const WALK_DISTANCE_PER_TICK := 0.28
const ARRIVAL_RADIUS := 1.1

const HUNGER_EAT_THRESHOLD := 62.0
const HUNGER_URGENT_THRESHOLD := 88.0
const ENERGY_REST_THRESHOLD := 28.0
const ENERGY_URGENT_THRESHOLD := 7.0
const ENERGY_WAKE_THRESHOLD := 90.0

const SLEEP_START_MINUTE := 22 * 60
const SLEEP_END_MINUTE := 6 * 60
const EAT_DURATION_TICKS := 18
const REST_DURATION_TICKS := 75
const SOCIALIZE_DURATION_TICKS := 40
const IDLE_DURATION_TICKS := 4
const BLOCKED_RECOVERY_TICKS := 3

const IDLE_ENERGY_RATE := -0.045
const IDLE_HUNGER_RATE := 0.05
const WALK_ENERGY_RATE := -0.06
const WALK_HUNGER_RATE := 0.055
const WORK_ENERGY_RATE := -0.07
const WORK_HUNGER_RATE := 0.075
const SLEEP_ENERGY_RATE := 0.6
const SLEEP_HUNGER_RATE := 0.03
const REST_ENERGY_RATE := 0.35
const REST_HUNGER_RATE := 0.04
const EAT_HUNGER_RATE := -2.8
const SOCIAL_ENERGY_RATE := -0.04
const SOCIAL_HUNGER_RATE := 0.04

const REASON_NIGHT := "notte"

var _records: Array[NpcRecord] = []
var _by_id: Dictionary = {}
var _places: NpcPlaceRegistry = null
var _route_graph: NpcRouteGraph = null
var _economy: EconomySystem = null
var _start_tick: int = 0
var _last_tick: int = -1
var _initialized: bool = false
var _initial_snapshots: Array[Dictionary] = []
var _warned: Dictionary = {}


func _init(
	records: Array[NpcRecord],
	places: NpcPlaceRegistry,
	route_graph: NpcRouteGraph
) -> void:
	_records = records
	_places = places
	_route_graph = route_graph
	_rebuild_index()


func get_system_name() -> String:
	return SYSTEM_NAME


func get_records() -> Array[NpcRecord]:
	return _records


func get_record_count() -> int:
	return _records.size()


func get_record(npc_id: String) -> NpcRecord:
	return _by_id.get(npc_id, null) as NpcRecord


func get_place_registry() -> NpcPlaceRegistry:
	return _places


func get_route_graph() -> NpcRouteGraph:
	return _route_graph


func set_economy_system(economy: EconomySystem) -> void:
	_economy = economy


func get_economy_system() -> EconomySystem:
	return _economy


func get_last_tick() -> int:
	return _last_tick


## Places the inhabitants at home and decides their first goal. Called by the
## world once the places and the route graph exist. Safe to call twice.
func initialize(start_tick: int) -> void:
	if _initialized:
		return
	_start_tick = maxi(start_tick, 0)
	_last_tick = _start_tick - 1
	_initialized = true
	_initial_snapshots.clear()
	_validate_unique_ids()
	_assign_homes()
	for record in _records:
		record.needs.clamp_all()
		record.personality.clamp_all()
		_choose_goal(record, _start_tick, _start_tick % SimulationClock.MINUTES_PER_DAY)
		_initial_snapshots.append(record.to_dict())
	GameLog.info(TAG, summary())


## One simulated minute. This is the only entry point and it updates **all**
## records, independent of any view.
func on_tick(tick: int, clock: SimulationClock) -> void:
	if not _initialized:
		initialize(tick)
	var minute := clock.get_minute_of_day()
	for record in _records:
		_advance_needs(record)
		_update_record(record, tick, minute)
	_last_tick = tick


## Restores the state captured right after [method initialize].
func reset() -> void:
	if not _initialized:
		return
	for index in _records.size():
		if index < _initial_snapshots.size():
			_records[index].from_dict(_initial_snapshots[index])
	_last_tick = _start_tick - 1
	_warned.clear()


## Snapshot for the future `persistence` module.
func to_dict() -> Dictionary:
	var records_data: Array = []
	for record in _records:
		records_data.append(record.to_dict())
	return {
		"initialized": _initialized,
		"start_tick": _start_tick,
		"last_tick": _last_tick,
		"records": records_data,
	}


func from_dict(data: Dictionary) -> void:
	var restored: Array[NpcRecord] = []
	for record_data in data.get("records", []):
		var record := NpcRecord.new()
		record.from_dict(record_data as Dictionary)
		restored.append(record)
	if restored.is_empty():
		return
	_records = restored
	_rebuild_index()
	_start_tick = int(data.get("start_tick", 0))
	_last_tick = int(data.get("last_tick", -1))
	_initialized = bool(data.get("initialized", true))
	_initial_snapshots.clear()
	for record in _records:
		_initial_snapshots.append(record.to_dict())


## Returns every problem that would make the population unusable. An empty
## array means "consistent"; the world logs the result at boot.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	var seen: Dictionary = {}
	for record in _records:
		if record.id.is_empty():
			problems.append("a record has an empty id")
			continue
		if seen.has(record.id):
			problems.append("duplicate NPC id '%s'" % record.id)
		seen[record.id] = true
		if not record.position.is_finite():
			problems.append("%s: non-finite position" % record.id)
		if not record.needs.are_valid():
			problems.append("%s: needs out of range" % record.id)
		if _places != null and not record.home_place_id.is_empty() \
				and not _places.has_place(record.home_place_id):
			problems.append("%s: home place missing" % record.id)
		if _places != null and not record.work_place_id.is_empty() \
				and not _places.has_place(record.work_place_id):
			problems.append("%s: workplace missing" % record.id)
		if record.work_end_minute <= record.work_start_minute:
			problems.append("%s: invalid work window" % record.id)
	if _route_graph != null and _places != null:
		for place_id in _route_graph.get_unreachable_place_ids():
			if _places.has_place(place_id):
				problems.append("place '%s' is unreachable" % place_id)
	return problems


func summary() -> String:
	var unreachable := 0
	if _route_graph != null:
		unreachable = _route_graph.get_unreachable_place_ids().size()
	return "%d abitanti, %d luoghi, %d nodi di percorso, %d luoghi irraggiungibili" % [
		_records.size(),
		_places.get_count() if _places != null else 0,
		_route_graph.get_node_count() if _route_graph != null else 0,
		unreachable,
	]


# --- state machine -----------------------------------------------------------


func _update_record(record: NpcRecord, tick: int, minute: int) -> void:
	match record.activity:
		NpcRecord.Activity.WALKING:
			if _has_urgent_need(record) and record.goal != NpcRecord.Goal.SEEK_FOOD:
				_choose_goal(record, tick, minute)
				return
			if record.goal == NpcRecord.Goal.GO_TO_WORK \
					and not record.is_within_work_hours(minute):
				_choose_goal(record, tick, minute)
				return
			if record.goal == NpcRecord.Goal.SLEEP and not _is_sleep_window(minute) \
					and record.needs.energy > ENERGY_REST_THRESHOLD:
				_choose_goal(record, tick, minute)
				return
			# Night falls while somebody is still walking to the square or to a
			# rest bench: re-decide at once, so bedtime is not delayed by the
			# length of a free-time trip.
			if _is_sleep_window(minute) and (
				record.goal == NpcRecord.Goal.SOCIALIZE
				or record.goal == NpcRecord.Goal.WANDER
				or record.goal == NpcRecord.Goal.REST
			):
				_choose_goal(record, tick, minute)
				return
			if _move_along_path(record):
				var place := _places.get_place(record.destination_place_id)
				record.has_destination = false
				if place != null:
					_enter_place(record, place, tick, minute, record.goal)
				else:
					_choose_goal(record, tick, minute)
		NpcRecord.Activity.WORKING:
			if not record.is_within_work_hours(minute) or _has_urgent_need(record):
				_choose_goal(record, tick, minute)
		NpcRecord.Activity.SLEEPING:
			if _should_wake(record, minute):
				_choose_goal(record, tick, minute)
		NpcRecord.Activity.RESTING, NpcRecord.Activity.EATING, \
				NpcRecord.Activity.SOCIALIZING:
			record.action_ticks_left -= 1
			if record.action_ticks_left <= 0:
				_choose_goal(record, tick, minute)
		NpcRecord.Activity.BLOCKED:
			record.blocked_ticks -= 1
			if record.blocked_ticks <= 0:
				_choose_goal(record, tick, minute)
		NpcRecord.Activity.IDLE:
			if record.action_ticks_left > 0:
				record.action_ticks_left -= 1
			else:
				_choose_goal(record, tick, minute)
		_:
			_choose_goal(record, tick, minute)


func _choose_goal(record: NpcRecord, tick: int, minute: int) -> void:
	if _places == null:
		_set_blocked(record, tick, "Registro dei luoghi assente.")
		return
	# 1. Urgent survival needs override everything else.
	if _choose_urgent_need(record, tick, minute):
		return
	# 2. Work takes precedence over comfort while the shift is running, but a
	# genuinely hungry worker still stops to eat.
	if record.is_within_work_hours(minute) and _choose_work(record, tick, minute):
		return
	# 3. Night sleep.
	if _is_sleep_window(minute):
		_seek_sleep(record, tick, minute)
		return
	# 4. Ordinary needs and free time.
	if _choose_ordinary_need(record, tick, minute):
		return
	_spend_free_time(record, tick, minute)


## Returns true when an urgent need consumed the decision.
func _choose_urgent_need(record: NpcRecord, tick: int, minute: int) -> bool:
	if record.needs.hunger >= HUNGER_URGENT_THRESHOLD:
		_seek_food(record, tick, minute)
		return true
	if record.needs.energy <= ENERGY_URGENT_THRESHOLD:
		_seek_rest(record, tick, minute, true)
		return true
	return false


## Returns true when the work window owned the decision. A worker who cannot
## reach their workplace falls through to ordinary life instead of freezing.
func _choose_work(record: NpcRecord, tick: int, minute: int) -> bool:
	if record.needs.hunger >= HUNGER_EAT_THRESHOLD:
		if _economy == null or EconomyRules.has_available_food_for(_economy, record.id):
			_seek_food(record, tick, minute)
			return true
	if not _can_work(record):
		return false
	_go_to_work(record, tick, minute)
	return true


## Returns true when hunger or tiredness consumed the decision.
func _choose_ordinary_need(record: NpcRecord, tick: int, minute: int) -> bool:
	if record.needs.hunger >= HUNGER_EAT_THRESHOLD:
		_seek_food(record, tick, minute)
		return true
	if record.needs.energy <= ENERGY_REST_THRESHOLD:
		_seek_rest(record, tick, minute, true)
		return true
	return false


func _go_to_work(record: NpcRecord, tick: int, minute: int) -> void:
	var place := _places.get_place(record.work_place_id)
	if place == null:
		_spend_free_time(record, tick, minute)
		return
	if _is_at_place(record, place):
		_start_working(record, tick, minute)
		return
	if not _travel_to(
		record, place, NpcRecord.Goal.GO_TO_WORK, tick, minute, "turno di lavoro"
	):
		# If the workplace cannot be reached, do not freeze: live the free time
		# instead, and let the warning above explain the problem once. A BLOCKED
		# record keeps its recovery countdown.
		if record.activity == NpcRecord.Activity.BLOCKED:
			return
		_spend_free_time(record, tick, minute)


func _start_working(record: NpcRecord, tick: int, minute: int) -> void:
	_set_current_place(record, _places.get_place(record.work_place_id))
	record.set_goal(NpcRecord.Goal.WORK, "turno di lavoro")
	record.set_activity(NpcRecord.Activity.WORKING, tick)
	record.action_ticks_left = 0
	_clear_destination(record)
	if not record.is_within_work_hours(minute):
		_choose_goal(record, tick, minute)


func _seek_food(record: NpcRecord, tick: int, minute: int) -> void:
	var food := _find_reachable_food(record, minute)
	if food == null:
		# No food is available right now: wait and retry instead of pretending to
		# eat. The condition is explicit in goal_reason and in the UI summary.
		record.set_goal(NpcRecord.Goal.SEEK_FOOD, "nessun cibo disponibile")
		record.set_activity(NpcRecord.Activity.IDLE, tick)
		record.action_ticks_left = IDLE_DURATION_TICKS
		_clear_destination(record)
		return
	if _is_at_place(record, food):
		_start_eating(record, food, tick, minute)
		return
	if not _travel_to(record, food, NpcRecord.Goal.SEEK_FOOD, tick, minute, "fame"):
		# A failed trip left the record in BLOCKED: let the recovery countdown
		# run instead of overwriting the diagnostic with a fake idle state.
		if record.activity == NpcRecord.Activity.BLOCKED:
			return
		# No reachable food: wait where we are, never teleport.
		record.set_goal(NpcRecord.Goal.SEEK_FOOD, "cibo non raggiungibile")
		record.set_activity(NpcRecord.Activity.IDLE, tick)
		record.action_ticks_left = IDLE_DURATION_TICKS
		_clear_destination(record)


func _start_eating(record: NpcRecord, place: NpcPlace, tick: int, minute: int) -> void:
	if not place.is_food_available(minute) and place.kind != NpcPlace.Kind.HOME:
		_choose_goal(record, tick, minute)
		return
	var fed := true
	if _economy != null:
		fed = _economy.request_meal_for_npc(record, tick)
	record.last_meal_satisfied = fed
	_set_current_place(record, place)
	record.set_goal(
		NpcRecord.Goal.EAT,
		"fame" if fed else "carenza di cibo nel villaggio"
	)
	record.set_activity(NpcRecord.Activity.EATING, tick)
	record.action_ticks_left = EAT_DURATION_TICKS
	_clear_destination(record)


func _seek_rest(record: NpcRecord, tick: int, minute: int, _urgent: bool) -> void:
	var place := _find_reachable_rest_place(record, minute)
	if place == null:
		# Sleep/rest where the character stands: worse, but honest and safe.
		_start_sleeping(record, tick, minute, "riposo di fortuna")
		return
	var goal := NpcRecord.Goal.SLEEP if _is_sleep_window(minute) \
		else NpcRecord.Goal.REST
	if _is_at_place(record, place):
		_enter_place(record, place, tick, minute, goal)
		return
	if not _travel_to(record, place, goal, tick, minute, "riposo"):
		if record.activity == NpcRecord.Activity.BLOCKED:
			return
		if goal == NpcRecord.Goal.SLEEP:
			_start_sleeping(record, tick, minute, "riposo di fortuna")
		else:
			_start_resting(record, tick)


func _seek_sleep(record: NpcRecord, tick: int, minute: int) -> void:
	var place := _find_reachable_rest_place(record, minute)
	if place == null:
		_start_sleeping(record, tick, minute, "notte")
		return
	if _is_at_place(record, place):
		_start_sleeping(record, tick, minute, "notte")
		return
	if not _travel_to(record, place, NpcRecord.Goal.SLEEP, tick, minute, "notte"):
		if record.activity == NpcRecord.Activity.BLOCKED:
			return
		_start_sleeping(record, tick, minute, "notte")


func _start_sleeping(record: NpcRecord, tick: int, _minute: int, reason: String) -> void:
	record.set_goal(NpcRecord.Goal.SLEEP, reason)
	record.set_activity(NpcRecord.Activity.SLEEPING, tick)
	record.action_ticks_left = 0
	_clear_destination(record)


func _start_resting(record: NpcRecord, tick: int) -> void:
	record.set_goal(NpcRecord.Goal.REST, "recuperare energie")
	record.set_activity(NpcRecord.Activity.RESTING, tick)
	record.action_ticks_left = REST_DURATION_TICKS
	_clear_destination(record)


func _start_socializing(record: NpcRecord, tick: int) -> void:
	record.set_goal(NpcRecord.Goal.SOCIALIZE, "tempo libero")
	record.set_activity(NpcRecord.Activity.SOCIALIZING, tick)
	record.action_ticks_left = SOCIALIZE_DURATION_TICKS
	_clear_destination(record)


func _spend_free_time(record: NpcRecord, tick: int, minute: int) -> void:
	var candidates := _reachable_social_places(record, minute)
	record.leisure_cursor += 1
	if candidates.is_empty():
		record.set_goal(NpcRecord.Goal.WANDER, "nessun luogo di ritrovo aperto")
		record.set_activity(NpcRecord.Activity.IDLE, tick)
		record.action_ticks_left = IDLE_DURATION_TICKS
		_clear_destination(record)
		return
	var place: NpcPlace = candidates[record.leisure_cursor % candidates.size()]
	var wants_company := record.personality.sociability >= 45
	if record.needs.wellbeing < 45.0:
		wants_company = true
	var goal := NpcRecord.Goal.SOCIALIZE if wants_company else NpcRecord.Goal.WANDER
	if _is_at_place(record, place):
		_enter_place(record, place, tick, minute, goal)
		return
	if not _travel_to(
		record, place, goal, tick, minute,
		"tempo libero" if wants_company else "passeggiata"
	):
		if record.activity == NpcRecord.Activity.BLOCKED:
			return
		record.set_goal(NpcRecord.Goal.WANDER, "passeggiata")
		record.set_activity(NpcRecord.Activity.IDLE, tick)
		record.action_ticks_left = IDLE_DURATION_TICKS


func _enter_place(
	record: NpcRecord, place: NpcPlace, tick: int, minute: int, goal: int
) -> void:
	_set_current_place(record, place)
	_clear_destination(record)
	match goal:
		NpcRecord.Goal.GO_TO_WORK:
			_start_working(record, tick, minute)
		NpcRecord.Goal.SEEK_FOOD:
			_start_eating(record, place, tick, minute)
		NpcRecord.Goal.SLEEP:
			_start_sleeping(record, tick, minute, "notte")
		NpcRecord.Goal.REST:
			_start_resting(record, tick)
		NpcRecord.Goal.SOCIALIZE:
			_start_socializing(record, tick)
		NpcRecord.Goal.WANDER:
			record.set_goal(NpcRecord.Goal.WANDER, "passeggiata")
			record.set_activity(NpcRecord.Activity.IDLE, tick)
			record.action_ticks_left = IDLE_DURATION_TICKS
		_:
			_choose_goal(record, tick, minute)


# --- movement ----------------------------------------------------------------


func _travel_to(
	record: NpcRecord,
	place: NpcPlace,
	goal: int,
	tick: int,
	minute: int,
	reason: String
) -> bool:
	if place == null:
		_set_blocked(record, tick, "Destinazione sconosciuta.")
		return false
	if not _is_reachable(place):
		_warn_once(
			"%s|%s" % [record.id, place.id],
			"%s: '%s' non è raggiungibile." % [record.display_name, place.display_name]
		)
		_set_blocked(record, tick, "'%s' non raggiungibile." % place.display_name)
		return false
	if _is_at_place(record, place):
		_enter_place(record, place, tick, minute, goal)
		return true
	var path := PackedVector2Array()
	if _route_graph != null:
		path = _route_graph.find_path(record.position, place.id)
	else:
		path = PackedVector2Array([record.position, place.position])
	if path.is_empty():
		_set_blocked(record, tick, "Nessun percorso verso '%s'." % place.display_name)
		return false
	record.path = path
	record.path_index = 0
	record.destination = place.position
	record.destination_place_id = place.id
	record.destination_place_name = place.display_name
	record.has_destination = true
	record.set_goal(goal, reason)
	record.set_activity(NpcRecord.Activity.WALKING, tick)
	return true


## Moves at most [constant WALK_DISTANCE_PER_TICK] units and returns true when
## the end of the path has been reached. It never assigns the destination: the
## only way a position changes is walking along the path, step by step.
func _move_along_path(record: NpcRecord) -> bool:
	var remaining := WALK_DISTANCE_PER_TICK
	while remaining > 0.0 and record.path_index < record.path.size():
		var target: Vector2 = record.path[record.path_index]
		var offset := target - record.position
		var distance := offset.length()
		if distance <= 0.0001:
			record.path_index += 1
			continue
		if distance <= remaining:
			record.position = target
			record.path_index += 1
			remaining -= distance
		else:
			record.position += offset / distance * remaining
			remaining = 0.0
	return record.path_index >= record.path.size()


func _set_blocked(record: NpcRecord, tick: int, reason: String) -> void:
	record.set_goal(NpcRecord.Goal.BLOCKED, reason)
	record.set_activity(NpcRecord.Activity.BLOCKED, tick)
	record.blocked_ticks = BLOCKED_RECOVERY_TICKS
	record.action_ticks_left = 0
	_clear_destination(record)


func _clear_destination(record: NpcRecord) -> void:
	record.has_destination = false
	record.destination = record.position
	record.destination_place_id = ""
	record.destination_place_name = ""
	record.path = PackedVector2Array()
	record.path_index = 0


# --- needs -------------------------------------------------------------------


func _advance_needs(record: NpcRecord) -> void:
	var needs := record.needs
	match record.activity:
		NpcRecord.Activity.WORKING:
			needs.energy += WORK_ENERGY_RATE
			needs.hunger += WORK_HUNGER_RATE
		NpcRecord.Activity.WALKING:
			needs.energy += WALK_ENERGY_RATE
			needs.hunger += WALK_HUNGER_RATE
		NpcRecord.Activity.SLEEPING:
			needs.energy += SLEEP_ENERGY_RATE
			needs.hunger += SLEEP_HUNGER_RATE
		NpcRecord.Activity.RESTING:
			needs.energy += REST_ENERGY_RATE
			needs.hunger += REST_HUNGER_RATE
		NpcRecord.Activity.EATING:
			if record.last_meal_satisfied:
				needs.hunger += EAT_HUNGER_RATE
			else:
				needs.hunger = maxf(
					needs.hunger - 0.4, EconomyRules.SHORTAGE_HUNGER_FLOOR
				)
		NpcRecord.Activity.SOCIALIZING:
			needs.energy += SOCIAL_ENERGY_RATE
			needs.hunger += SOCIAL_HUNGER_RATE
		_:
			needs.energy += IDLE_ENERGY_RATE
			needs.hunger += IDLE_HUNGER_RATE
	_advance_wellbeing(record)
	needs.clamp_all()


func _advance_wellbeing(record: NpcRecord) -> void:
	var needs := record.needs
	if needs.hunger >= 85.0 or needs.energy <= 10.0:
		needs.wellbeing -= 0.09
		return
	match record.activity:
		NpcRecord.Activity.EATING:
			if record.last_meal_satisfied:
				needs.wellbeing += 0.14
			else:
				needs.wellbeing += EconomyRules.SHORTAGE_DAILY_WELLBEING_DRIFT
		NpcRecord.Activity.SOCIALIZING:
			needs.wellbeing += 0.14
		NpcRecord.Activity.SLEEPING:
			needs.wellbeing += 0.05
		NpcRecord.Activity.RESTING:
			needs.wellbeing += 0.07
		_:
			var target := 55.0 + float(record.personality.calmness) * 0.14
			needs.wellbeing = move_toward(needs.wellbeing, target, 0.015)


# --- decisions ---------------------------------------------------------------


func _can_work(record: NpcRecord) -> bool:
	if record.work_place_id.is_empty():
		return false
	var place := _places.get_place(record.work_place_id)
	if place == null:
		return false
	if _is_reachable(place):
		return true
	_warn_once(
		"%s|work" % record.id,
		"%s: luogo di lavoro '%s' irraggiungibile." % [record.display_name, place.id]
	)
	return false


func _find_reachable_food(record: NpcRecord, minute: int) -> NpcPlace:
	# Public food places first, so the inn and the market are actually used;
	# home is the fallback pantry.
	var best: NpcPlace = null
	var best_distance := INF
	for place in _places.places_of_kind(NpcPlace.Kind.FOOD):
		if not place.is_food_available(minute) or not _is_reachable(place):
			continue
		var distance := record.position.distance_squared_to(place.position)
		if distance < best_distance:
			best_distance = distance
			best = place
	if best != null:
		return best
	var home := _places.get_place(record.home_place_id)
	if home != null and home.serves_food and _is_reachable(home):
		return home
	return null


func _find_reachable_rest_place(record: NpcRecord, minute: int) -> NpcPlace:
	# Your own home first: sleeping at a neighbour's table reads as a bug, not
	# as a preference. The nearest other rest place is the fallback.
	var home := _places.get_place(record.home_place_id)
	if home != null and home.is_rest_place() and home.is_open(minute) and _is_reachable(home):
		return home
	var best: NpcPlace = null
	var best_distance := INF
	for place in _places.all_places():
		if not place.is_rest_place() or not place.is_open(minute):
			continue
		if not _is_reachable(place):
			continue
		var distance := record.position.distance_squared_to(place.position)
		if distance < best_distance:
			best_distance = distance
			best = place
	return best


func _reachable_social_places(record: NpcRecord, minute: int) -> Array[NpcPlace]:
	var result: Array[NpcPlace] = []
	for place in _places.all_places():
		if not place.is_social_place() or not place.is_open(minute):
			continue
		if not _is_reachable(place):
			continue
		# Prefer somewhere else: standing still is not "spending free time".
		if place.id == record.current_place_id and _places.get_count() > 1:
			continue
		result.append(place)
	return result


func _first_reachable_place() -> NpcPlace:
	if _places == null:
		return null
	for place in _places.all_places():
		if _is_reachable(place):
			return place
	return null


func _is_reachable(place: NpcPlace) -> bool:
	if place == null or _route_graph == null:
		return false
	return _route_graph.is_place_reachable(place.id)


func _is_at_place(record: NpcRecord, place: NpcPlace) -> bool:
	return record.position.distance_to(place.position) <= ARRIVAL_RADIUS


func _is_sleep_window(minute: int) -> bool:
	return minute >= SLEEP_START_MINUTE or minute < SLEEP_END_MINUTE


func _should_wake(record: NpcRecord, minute: int) -> bool:
	if record.goal_reason == REASON_NIGHT:
		return not _is_sleep_window(minute)
	return record.needs.energy >= ENERGY_WAKE_THRESHOLD


func _has_urgent_need(record: NpcRecord) -> bool:
	return record.needs.hunger >= HUNGER_URGENT_THRESHOLD \
		or record.needs.energy <= ENERGY_URGENT_THRESHOLD


# --- initialization ----------------------------------------------------------


func _assign_homes() -> void:
	var homes: Array[NpcPlace] = []
	if _places != null:
		homes = _places.home_places()
	var fallback := _first_reachable_place()
	for index in _records.size():
		var record := _records[index]
		var home: NpcPlace = null
		if not homes.is_empty():
			home = homes[index % homes.size()]
		elif fallback != null:
			home = fallback
		if home == null:
			record.position = Vector2.ZERO
			record.home_place_id = ""
			record.current_place_id = ""
			record.current_place_name = ""
			_set_blocked(record, _start_tick, "Nessun luogo abitabile disponibile.")
			continue
		record.home_place_id = home.id
		if not _is_reachable(home):
			var alternative := _first_reachable_place()
			if alternative != null and alternative != home:
				_warn_once(
					"%s|home" % record.id,
					"%s: casa '%s' irraggiungibile, uso '%s'."
					% [record.display_name, home.id, alternative.display_name]
				)
				home = alternative
				record.home_place_id = home.id
		record.position = home.position
		record.destination = home.position
		record.current_place_id = home.id
		record.current_place_name = home.display_name
		record.has_destination = false
		record.path = PackedVector2Array()
		record.path_index = 0
		record.blocked_ticks = 0


func _rebuild_index() -> void:
	_by_id.clear()
	for record in _records:
		if record.id.is_empty():
			continue
		if _by_id.has(record.id):
			push_error("NpcSimulationSystem: duplicate NPC id '%s'." % record.id)
			continue
		_by_id[record.id] = record


func _validate_unique_ids() -> void:
	var seen: Dictionary = {}
	for record in _records:
		if seen.has(record.id):
			push_error("NpcSimulationSystem: duplicate NPC id '%s'." % record.id)
		seen[record.id] = true


func _set_current_place(record: NpcRecord, place: NpcPlace) -> void:
	if place == null:
		return
	record.current_place_id = place.id
	record.current_place_name = place.display_name


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	GameLog.warning(TAG, message)
