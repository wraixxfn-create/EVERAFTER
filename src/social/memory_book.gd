class_name MemoryBook
extends RefCounted
## Every memory of every inhabitant, in one bounded store.
##
## Inhabitants do not keep everything. The book has a capacity per character
## ([member capacity_per_npc]) and an importance floor
## ([member importance_floor]): a memory below the floor is not stored at all,
## which is what stops a hundred small talk exchanges from filling a life. When
## the capacity is reached the weakest memory leaves, following the documented
## rule in [method NpcMemory.retention_score] — importance first, recency only
## to break ties.
##
## Nothing is dropped silently:
## * every eviction increments [member evicted_count];
## * an eviction of a memory at or above [constant NpcMemory.PERMANENT_IMPORTANCE]
##   is additionally counted in [member evicted_protected_count] and logged with
##   its text, and it only happens when the book contains nothing else to drop;
## * the objective event stays in `SocialSystem`'s event log, so forgetting is a
##   property of the character, never of the world.
##
## Pure data: no node, no scene, no clock of its own. The current day is always
## passed in by the caller, which keeps every method deterministic.

const TAG := "Memory"
const DEFAULT_CAPACITY := 24
const DEFAULT_IMPORTANCE_FLOOR := 12

var capacity_per_npc: int = DEFAULT_CAPACITY
var importance_floor: int = DEFAULT_IMPORTANCE_FLOOR

var evicted_count: int = 0
var evicted_protected_count: int = 0
## Memories refused because they were too minor to be worth remembering.
var rejected_count: int = 0

var _by_owner: Dictionary = {}
## Insertion order of the owners, for stable iteration.
var _owners: Array[String] = []
var _next_id: int = 1


## Applies the configured limits. A capacity below 1 would make every memory
## transient, so it is clamped instead of trusted blindly.
func configure(capacity: int, floor_importance: int) -> void:
	capacity_per_npc = maxi(capacity, 1)
	importance_floor = clampi(floor_importance, 0, NpcMemory.IMPORTANCE_MAX)


## Sequential, stable memory id. Sequential on purpose: the counter is part of
## the serialised state, so a reloaded world keeps issuing unique ids.
func next_memory_id() -> String:
	var memory_id := "mem_%06d" % _next_id
	_next_id += 1
	return memory_id


## Stores a memory. Returns false when it was refused (too minor, or missing
## data), true when it is now part of the book. The id is assigned here when the
## caller left it empty, so callers cannot invent colliding ids.
func remember(memory: NpcMemory) -> bool:
	if memory == null or memory.owner_id.is_empty() or memory.summary.is_empty():
		return false
	if memory.importance < importance_floor:
		rejected_count += 1
		return false
	if memory.id.is_empty():
		memory.id = next_memory_id()
	var list := _list_for(memory.owner_id)
	list.append(memory)
	_enforce_capacity(memory.owner_id, list, memory.day)
	return true


## Memories of one inhabitant, oldest first. A copy: a caller cannot mutate the
## book without going through it.
func memories_of(npc_id: String) -> Array[NpcMemory]:
	var result: Array[NpcMemory] = []
	if not _by_owner.has(npc_id):
		return result
	for memory in _by_owner[npc_id]:
		result.append(memory as NpcMemory)
	return result


## The memories that matter most right now, by retention score. This is what the
## UI shows and what the decision rules consult.
func relevant_memories_of(npc_id: String, current_day: int, limit: int) -> Array[NpcMemory]:
	var result := memories_of(npc_id)
	result.sort_custom(_higher_retention_first.bind(current_day))
	if limit >= 0 and result.size() > limit:
		result.resize(maxi(limit, 0))
	return result


## The most recently formed memories, newest first.
func latest_memories_of(npc_id: String, limit: int) -> Array[NpcMemory]:
	var result := memories_of(npc_id)
	result.reverse()
	if limit >= 0 and result.size() > limit:
		result.resize(maxi(limit, 0))
	return result


func count_of(npc_id: String) -> int:
	if not _by_owner.has(npc_id):
		return 0
	return (_by_owner[npc_id] as Array[NpcMemory]).size()


func total_count() -> int:
	var total := 0
	for owner_id in _owners:
		total += (_by_owner[owner_id] as Array[NpcMemory]).size()
	return total


func owner_ids() -> Array[String]:
	return _owners.duplicate()


func find_memory(memory_id: String) -> NpcMemory:
	if memory_id.is_empty():
		return null
	for owner_id in _owners:
		for memory in _by_owner[owner_id]:
			if (memory as NpcMemory).id == memory_id:
				return memory as NpcMemory
	return null


func forget(npc_id: String, memory_id: String) -> bool:
	if not _by_owner.has(npc_id):
		return false
	var list := _by_owner[npc_id] as Array[NpcMemory]
	for index in list.size():
		if list[index].id == memory_id:
			list.remove_at(index)
			return true
	return false


func clear() -> void:
	_by_owner.clear()
	_owners.clear()


## Drops the memories of inhabitants the world no longer knows, and any memory
## that points at an unknown participant. Returns how many were removed.
func remove_orphans(known_ids: Dictionary) -> int:
	var removed := 0
	var empty_owners: Array[String] = []
	for owner_id in _owners:
		if not known_ids.has(owner_id):
			removed += (_by_owner[owner_id] as Array[NpcMemory]).size()
			_by_owner.erase(owner_id)
			empty_owners.append(owner_id)
			continue
		var list := _by_owner[owner_id] as Array[NpcMemory]
		for index in range(list.size() - 1, -1, -1):
			var memory := list[index]
			var dangling := false
			for other_id in memory.other_ids:
				if not known_ids.has(other_id):
					dangling = true
					break
			if dangling:
				list.remove_at(index)
				removed += 1
		if list.is_empty():
			_by_owner.erase(owner_id)
			empty_owners.append(owner_id)
	for owner_id in empty_owners:
		_owners.erase(owner_id)
	return removed


## Human readable problems. An empty array means the book is consistent.
func validate(known_ids: Dictionary = {}) -> PackedStringArray:
	var problems: PackedStringArray = []
	var seen_ids: Dictionary = {}
	for owner_id in _owners:
		if not _by_owner.has(owner_id):
			problems.append("owner '%s' is indexed but missing" % owner_id)
			continue
		var list := _by_owner[owner_id] as Array[NpcMemory]
		if list.size() > capacity_per_npc:
			problems.append(
				"'%s' holds %d memories, the capacity is %d"
				% [owner_id, list.size(), capacity_per_npc]
			)
		if not known_ids.is_empty() and not known_ids.has(owner_id):
			problems.append("memories of unknown inhabitant '%s'" % owner_id)
		for memory in list:
			if seen_ids.has(memory.id):
				problems.append("duplicate memory id '%s'" % memory.id)
			seen_ids[memory.id] = true
			if not memory.is_valid():
				problems.append("memory '%s' is invalid" % memory.id)
			if memory.owner_id != owner_id:
				problems.append("memory '%s' is stored under the wrong owner" % memory.id)
	return problems


func to_dict() -> Dictionary:
	var owners_data: Array = []
	for owner_id in _owners:
		var entries: Array = []
		for memory in _by_owner[owner_id]:
			entries.append((memory as NpcMemory).to_dict())
		owners_data.append({"owner_id": owner_id, "memories": entries})
	return {
		"owners": owners_data,
		"next_id": _next_id,
		"capacity_per_npc": capacity_per_npc,
		"importance_floor": importance_floor,
		"evicted_count": evicted_count,
		"evicted_protected_count": evicted_protected_count,
		"rejected_count": rejected_count,
	}


func from_dict(data: Dictionary) -> void:
	clear()
	capacity_per_npc = maxi(int(data.get("capacity_per_npc", capacity_per_npc)), 1)
	importance_floor = int(data.get("importance_floor", importance_floor))
	evicted_count = int(data.get("evicted_count", evicted_count))
	evicted_protected_count = int(data.get("evicted_protected_count", evicted_protected_count))
	rejected_count = int(data.get("rejected_count", rejected_count))
	_next_id = int(data.get("next_id", _next_id))
	for owner_entry in data.get("owners", []):
		var owner_data := owner_entry as Dictionary
		var owner_id := String(owner_data.get("owner_id", ""))
		if owner_id.is_empty() or _by_owner.has(owner_id):
			continue
		var list: Array[NpcMemory] = []
		for memory_data in owner_data.get("memories", []):
			var memory := NpcMemory.new()
			memory.from_dict(memory_data as Dictionary)
			if memory.id.is_empty() or memory.owner_id.is_empty():
				continue
			list.append(memory)
		_by_owner[owner_id] = list
		_owners.append(owner_id)


# --- internals ---------------------------------------------------------------


func _list_for(npc_id: String) -> Array[NpcMemory]:
	if not _by_owner.has(npc_id):
		var created: Array[NpcMemory] = []
		_by_owner[npc_id] = created
		_owners.append(npc_id)
	return _by_owner[npc_id] as Array[NpcMemory]


## Applies the capacity limit. The victim is the memory with the lowest
## retention score (oldest first on a tie); a protected memory is only chosen
## when every other memory is protected too.
func _enforce_capacity(npc_id: String, list: Array[NpcMemory], current_day: int) -> void:
	while list.size() > capacity_per_npc:
		var victim_index := _weakest_index(list, current_day)
		if victim_index < 0:
			return
		var victim := list[victim_index]
		list.remove_at(victim_index)
		evicted_count += 1
		if victim.is_protected():
			evicted_protected_count += 1
			GameLog.warning(
				TAG,
				(
					"%s ha dimenticato un ricordo importante (capacità %d): %s"
					% [npc_id, capacity_per_npc, victim.summary]
				)
			)


## Index of the memory to drop, or -1 when the list is empty. Protected memories
## are excluded as long as at least one unprotected memory exists.
func _weakest_index(list: Array[NpcMemory], current_day: int) -> int:
	var candidates: Array[int] = []
	for index in list.size():
		if list[index].is_protected():
			continue
		candidates.append(index)
	if candidates.is_empty():
		for index in list.size():
			candidates.append(index)
	var best := -1
	var best_memory: NpcMemory = null
	for index in candidates:
		var memory := list[index]
		if best_memory == null or _is_weaker(memory, best_memory, current_day):
			best = index
			best_memory = memory
	return best


static func _is_weaker(
	candidate: NpcMemory, current_best: NpcMemory, current_day: int
) -> bool:
	var candidate_score := candidate.retention_score(current_day)
	var best_score := current_best.retention_score(current_day)
	if candidate_score != best_score:
		return candidate_score < best_score
	if candidate.day != current_best.day:
		return candidate.day < current_best.day
	return candidate.id < current_best.id


static func _higher_retention_first(first: NpcMemory, second: NpcMemory, current_day: int) -> bool:
	return _is_weaker(second, first, current_day)


func _to_string() -> String:
	return "%d ricordi di %d abitanti" % [total_count(), _owners.size()]
