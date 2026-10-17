class_name ChronicleBook
extends RefCounted
## Persistent, bounded book of the world's chronicle entries.
##
## Responsibilities:
## * Append-only API for producers (systems, persistence) to record noteworthy
##   events. Systems do not build `ChronicleEntry` instances themselves: they
##   call [method record] with the category, importance and summary.
## * Retention policy: a hard cap [member max_entries], evicting the least
##   important non-landmark entry first, then the oldest. Landmark entries
##   (importance >= [constant LANDMARK_IMPORTANCE]) are evicted only when
##   nothing else remains and the eviction is counted and logged.
## * Read access filtered by day, category or minimum importance for the UI.
##
## The book is **not** a SimulationSystem: it does not tick. Systems call
## [method record] when a noteworthy state change happens (e.g. economy
## detects a shortage, social detects a major relationship shift).
##
## Unit tests: `tests/unit/test_chronicle_book.gd`.

const TAG := \"Chronicle\"
## Default cap; can be reconfigured at runtime.
const DEFAULT_MAX_ENTRIES := 400
## Entries at or above this importance are protected from eviction as long as
## any evictable entry exists.
const LANDMARK_IMPORTANCE := 70
## Minimum importance of entries actually stored. Anything below this is
## ignored to avoid noise filling the book.
const MIN_STORED_IMPORTANCE := 8

var max_entries: int = DEFAULT_MAX_ENTRIES
var evicted_count: int = 0
var evicted_landmark_count: int = 0

var _entries: Array[ChronicleEntry] = []
var _by_id: Dictionary = {}
var _next_id: int = 1


func _init(capacity: int = DEFAULT_MAX_ENTRIES) -> void:
	max_entries = maxi(capacity, 10)


## Records a new entry and returns it (or null if the importance was below the
## floor). Safe to call with any number of subject/resource ids.
func record(
	category: int,
	day: int,
	minute_of_day: int,
	tick: int,
	importance: int,
	summary: String,
	subject_ids: Array = [],
	resource_ids: Array = [],
	details: Dictionary = {}
) -> ChronicleEntry:
	if importance < MIN_STORED_IMPORTANCE:
		return null
	if summary.is_empty():
		return null
	var entry := ChronicleEntry.new()
	entry.id = _allocate_id()
	entry.category = category
	entry.day = maxi(day, 1)
	entry.minute_of_day = clampi(minute_of_day, 0, SimulationClock.MINUTES_PER_DAY - 1)
	entry.tick = maxi(tick, 0)
	entry.importance = clampi(importance, IMPORTANCE_MIN, IMPORTANCE_MAX)
	entry.summary = summary
	for sid in subject_ids:
		var s := String(sid)
		if not s.is_empty():
			entry.subject_ids.append(s)
	for rid in resource_ids:
		var r := String(rid)
		if not r.is_empty():
			entry.resource_ids.append(r)
	entry.details = details.duplicate(true)
	_entries.append(entry)
	_by_id[entry.id] = entry
	_trim_to_capacity()
	return entry


## All entries, newest last. The returned array is a copy: callers cannot
## mutate the book through it.
func get_entries() -> Array[ChronicleEntry]:
	var copy: Array[ChronicleEntry] = []
	for e in _entries:
		copy.append(e)
	return copy


## Filtered access. Negative or zero values for [param day]/[param category]
## mean \"don't filter by that dimension\".
func query(
	min_importance: int = 0,
	day: int = 0,
	category: int = -1,
	limit: int = 0
) -> Array[ChronicleEntry]:
	var result: Array[ChronicleEntry] = []
	# Iterate newest first so a limit returns recent entries.
	for i in range(_entries.size() - 1, -1, -1):
		var e: ChronicleEntry = _entries[i]
		if e.importance < min_importance:
			continue
		if day > 0 and e.day != day:
			continue
		if category >= 0 and e.category != category:
			continue
		result.append(e)
		if limit > 0 and result.size() >= limit:
			break
	return result


func count() -> int:
	return _entries.size()


## The entry with the given id, or null.
func get_entry(entry_id: String) -> ChronicleEntry:
	return _by_id.get(entry_id, null) as ChronicleEntry


## First day present in the book (0 if empty).
func first_day() -> int:
	if _entries.is_empty():
		return 0
	return _entries[0].day


## Last day present in the book (0 if empty).
func last_day() -> int:
	if _entries.is_empty():
		return 0
	return _entries[_entries.size() - 1].day


## Drops entries that reference an NPC id that no longer exists. Called by
## the persistence layer after loading a save that may have shrunk.
func remove_subject_orphans(known_subject_ids: Dictionary) -> void:
	if known_subject_ids.is_empty():
		return
	for i in range(_entries.size() - 1, -1, -1):
		var e: ChronicleEntry = _entries[i]
		var keep := true
		for sid in e.subject_ids:
			# Subjects that look like system ids (not starting with \"npc_\") are
			# never considered orphans: the chronicle can refer to places or
			# future factions without having them registered.
			if not sid.begins_with(\"npc_\"):
				continue
			if not known_subject_ids.has(sid):
				keep = false
				break
		if not keep:
			_by_id.erase(e.id)
			_entries.remove_at(i)


func clear() -> void:
	_entries.clear()
	_by_id.clear()
	_next_id = 1
	evicted_count = 0
	evicted_landmark_count = 0


# --- serialisation -----------------------------------------------------------


func to_dict() -> Dictionary:
	var entry_data: Array = []
	for e in _entries:
		entry_data.append(e.to_dict())
	return {
		\"max_entries\": max_entries,
		\"next_id\": _next_id,
		\"evicted_count\": evicted_count,
		\"evicted_landmark_count\": evicted_landmark_count,
		\"entries\": entry_data,
	}


func from_dict(data: Dictionary) -> void:
	_entries.clear()
	_by_id.clear()
	max_entries = maxi(int(data.get(\"max_entries\", DEFAULT_MAX_ENTRIES)), 10)
	_next_id = maxi(int(data.get(\"next_id\", 1)), 1)
	evicted_count = int(data.get(\"evicted_count\", 0))
	evicted_landmark_count = int(data.get(\"evicted_landmark_count\", 0))
	for ed in data.get(\"entries\", []):
		var e := ChronicleEntry.new()
		e.from_dict(ed as Dictionary)
		if e.id.is_empty() or _by_id.has(e.id) or not e.is_valid():
			continue
		_entries.append(e)
		_by_id[e.id] = e
		_next_id = maxi(_next_id, _parse_id_tail(e.id) + 1)
	_trim_to_capacity()


# --- internals ---------------------------------------------------------------


func _allocate_id() -> String:
	var assigned := _next_id
	_next_id += 1
	return \"chr_%06d\" % assigned


## Extracts the numeric tail from an id like \"chr_000042\" -> 42. Returns 0 if
## the id does not match the expected shape.
static func _parse_id_tail(entry_id: String) -> int:
	if not entry_id.begins_with(\"chr_\"):
		return 0
	var tail := entry_id.trim_prefix(\"chr_\")
	return int(tail) if tail.is_valid_int() else 0


## Enforces the capacity by evicting the lowest-priority entry until the size
## fits. This uses a simple linear scan: the book is sized in the hundreds, so
## anything cleverer would be code we cannot verify.
func _trim_to_capacity() -> void:
	while _entries.size() > max_entries:
		var victim_index := _choose_victim_index()
		if victim_index < 0:
			break
		var victim := _entries[victim_index]
		_entries.remove_at(victim_index)
		_by_id.erase(victim.id)
		evicted_count += 1
		if victim.is_landmark():
			evicted_landmark_count += 1
			GameLog.warning(
				TAG,
				\"rimossa voce importante '%s' (imp. %d): il libro e' pieno.\"
				% [victim.id, victim.importance]
			)


func _choose_victim_index() -> int:
	if _entries.is_empty():
		return -1
	# Pass 1: evict the oldest non-landmark entry with the smallest importance.
	var best_index := -1
	var best_score := 1_000_000
	for i in range(_entries.size()):
		var e: ChronicleEntry = _entries[i]
		if e.is_landmark():
			continue
		# Lower importance wins ties; oldest (earlier index) wins ties.
		var score := e.importance * 1000 + i
		if score < best_score:
			best_score = score
			best_index = i
	if best_index >= 0:
		return best_index
	# Pass 2: everything left is a landmark. Evict the oldest least-important.
	best_index = 0
	var lowest_importance := _entries[0].importance
	for i in range(1, _entries.size()):
		var e: ChronicleEntry = _entries[i]
		if e.importance < lowest_importance:
			lowest_importance = e.importance
			best_index = i
	return best_index
