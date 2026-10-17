class_name SocialSystem
extends SimulationSystem
## Relationships, interactions and memories: the social layer of the village.
##
## A `SimulationSystem` like the others: pure logic, no node, no scene, no
## randomness, no wall clock. It is registered after `npc_life` and `economy`,
## so it reads the routine and the stocks the world has already produced this
## tick and never competes with them for the same state.
##
## ## What it owns
## * [member graph] — every relationship, stored once, keyed by the id pair;
## * [member memory_book] — every memory, bounded per inhabitant;
## * [member events] — the objective log of what happened, bounded, and the raw
##   material the chronicle phase will read.
##
## It owns none of the inhabitants' data: needs, positions and activities stay
## in `NpcRecord`, and this system only writes back the documented wellbeing
## effect of an interaction.
##
## ## What happens in a tick
## 1. inhabitants at the same place, close enough and not busy (sleeping,
##    walking, blocked) are grouped;
## 2. pairs are examined in a fixed order (place id, then roster order) and at
##    most [constant SocialRules.MAX_INTERACTIONS_PER_TICK] interactions are
##    produced per tick, so a crowd stays cheap and the log stays readable;
## 3. a pair that interacted less than [constant SocialRules.COOLDOWN_TICKS]
##    ticks ago is skipped: nothing is generated just to fill the silence;
## 4. [method SocialRules.decide_interaction] chooses the interaction, its
##    effects are applied, a [SocialEvent] is recorded and one memory per
##    participant is stored.
##
## ## Consequences
## A cooperation only happens when the asked character is willing
## ([method SocialRules.would_cooperate]), and willingness is computed from
## *their memories*. Help received raises it, a recent argument lowers it: the
## memory system changes what characters do, not only what the panel says.
## Accepted cooperation, help and arguments also move `needs.wellbeing`, so a
## social event is visible in the simulation state and not only in a text log.

const SYSTEM_NAME := "social"
const TAG := "Social"

const DEFAULT_MEMORY_CAPACITY := 24
const DEFAULT_MEMORY_IMPORTANCE_FLOOR := 12
const DEFAULT_EVENT_LOG_LIMIT := 160
## Dropping an event at or above this importance is logged, never silent.
const EVENT_LOG_PROTECT_IMPORTANCE := 50

var interaction_radius: float = SocialRules.PROXIMITY_RADIUS
var cooldown_ticks: int = SocialRules.COOLDOWN_TICKS
var event_log_limit: int = DEFAULT_EVENT_LOG_LIMIT
var daily_gain_cap: int = SocialRelationship.DEFAULT_DAILY_GAIN_CAP

## Read-only access for the UI, the tests and the future persistence module.
var graph: RelationshipGraph = RelationshipGraph.new()
var memory_book: MemoryBook = MemoryBook.new()
var events: Array[SocialEvent] = []
var dropped_event_count: int = 0

var _npc_system: NpcSimulationSystem = null
var _economy: EconomySystem = null
var _by_event_id: Dictionary = {}
var _next_event_id: int = 1
var _start_tick: int = 0
var _last_tick: int = -1
var _current_day: int = 1
var _initialized: bool = false
var _initial_snapshot: Dictionary = {}


func _init(npc_system: NpcSimulationSystem, economy: EconomySystem = null) -> void:
	_npc_system = npc_system
	_economy = economy


func get_system_name() -> String:
	return SYSTEM_NAME


func get_last_tick() -> int:
	return _last_tick


## Applies the tunable limits. Called by the world with the values from
## `GameConfig`, so the pacing can change without touching the code.
func configure(
	memory_capacity: int,
	memory_importance_floor: int,
	log_limit: int,
	radius: float,
	cooldown: int,
	gain_cap: int
) -> void:
	memory_book.configure(memory_capacity, memory_importance_floor)
	event_log_limit = maxi(log_limit, 1)
	interaction_radius = maxf(radius, 0.1)
	cooldown_ticks = maxi(cooldown, 0)
	daily_gain_cap = maxi(gain_cap, 1)
	_apply_daily_gain_cap()


## Builds the starting relationships and memories. Safe to call twice.
func initialize(start_tick: int) -> void:
	if _initialized:
		return
	_start_tick = maxi(start_tick, 0)
	_last_tick = _start_tick - 1
	_initialized = true
	if _npc_system != null:
		var records := _npc_system.get_records()
		graph = SocialRules.build_initial_relationships(records)
		SocialRules.seed_origin_memories(records, memory_book)
	_apply_daily_gain_cap()
	graph.remove_orphans(_known_ids())
	_drop_dangling_memories()
	_current_day = 1 + _start_tick / SimulationClock.MINUTES_PER_DAY
	_initial_snapshot = to_dict()
	GameLog.info(TAG, summary())


func on_tick(tick: int, clock: SimulationClock) -> void:
	if not _initialized:
		initialize(tick)
	_current_day = clock.get_display_day()
	_run_interactions(tick)
	_last_tick = tick


## Restores the state captured right after [method initialize].
func reset() -> void:
	if not _initialized:
		return
	from_dict(_initial_snapshot)


# --- read-only facade --------------------------------------------------------


func get_relationship_count() -> int:
	return graph.count()


func get_event_count() -> int:
	return events.size()


func get_event(event_id: String) -> SocialEvent:
	return _by_event_id.get(event_id, null) as SocialEvent


## The most recent events, newest first.
func get_events(limit: int = -1) -> Array[SocialEvent]:
	var result: Array[SocialEvent] = []
	for index in range(events.size() - 1, -1, -1):
		result.append(events[index])
		if limit >= 0 and result.size() >= limit:
			break
	return result


func get_memory_count(npc_id: String) -> int:
	return memory_book.count_of(npc_id)


## Willingness of [param asker_id] to work with [param partner_id] right now.
## Exposed so the UI and the tests read the same number the rules use.
func cooperation_willingness(asker_id: String, partner_id: String) -> int:
	return SocialRules.cooperation_willingness(
		asker_id, partner_id, graph, memory_book, _current_day
	)


# --- text for the panel ------------------------------------------------------
#
# The panel must stay readable, so short lines are built here instead of handing
# the UI raw dictionaries and letting it invent what a number means.


## Up to [param limit] lines, one per relevant relationship, strongest first.
func relationship_lines(npc_id: String, limit: int = 3) -> PackedStringArray:
	var lines: PackedStringArray = []
	if _npc_system == null:
		return lines
	for relationship in SocialRules.strongest_relationships(npc_id, graph, limit):
		var other := _npc_system.get_record(relationship.other_id(npc_id))
		var other_name := other.display_name if other != null else relationship.other_id(npc_id)
		lines.append(
			"%s · %s · fiducia %d · familiarità %d"
			% [
				other_name,
				relationship.kind_label(),
				relationship.trust_of(npc_id),
				relationship.familiarity,
			]
		)
	if lines.is_empty():
		lines.append("Nessuna relazione conosciuta.")
	return lines


## The documented reason behind the most recent change, when there is one. This
## is the answer to "why did this number move?": it names the event and the day.
func change_explanation(npc_id: String) -> String:
	var best: SocialRelationship = null
	for relationship in graph.relationships_of(npc_id):
		if relationship.last_change_event_id.is_empty():
			continue
		if best == null or relationship.last_change_tick > best.last_change_tick:
			best = relationship
	if best == null or _npc_system == null:
		return ""
	var other := _npc_system.get_record(best.other_id(npc_id))
	var other_name := other.display_name if other != null else best.other_id(npc_id)
	var event := get_event(best.last_change_event_id)
	if event == null:
		return "%s — con %s" % [best.last_change_reason, other_name]
	return "%s — con %s, giorno %d" % [best.last_change_reason, other_name, event.day]


## Up to [param limit] memories, the ones that matter most first.
func memory_lines(npc_id: String, limit: int = 3) -> PackedStringArray:
	var lines: PackedStringArray = []
	for memory in memory_book.relevant_memories_of(npc_id, _current_day, limit):
		lines.append("Giorno %d · %s — %s" % [memory.day, memory.kind_label(), memory.summary])
	if lines.is_empty():
		lines.append("Nessun ricordo rilevante.")
	return lines


# --- serialisation -----------------------------------------------------------


func to_dict() -> Dictionary:
	var event_entries: Array = []
	for event in events:
		event_entries.append(event.to_dict())
	return {
		"initialized": _initialized,
		"start_tick": _start_tick,
		"last_tick": _last_tick,
		"current_day": _current_day,
		"next_event_id": _next_event_id,
		"interaction_radius": interaction_radius,
		"cooldown_ticks": cooldown_ticks,
		"event_log_limit": event_log_limit,
		"daily_gain_cap": daily_gain_cap,
		"dropped_event_count": dropped_event_count,
		"graph": graph.to_dict(),
		"memories": memory_book.to_dict(),
		"events": event_entries,
	}


func from_dict(data: Dictionary) -> void:
	graph = RelationshipGraph.new()
	graph.from_dict(data.get("graph", {}))
	memory_book = MemoryBook.new()
	memory_book.from_dict(data.get("memories", {}))
	events.clear()
	_by_event_id.clear()
	for event_data in data.get("events", []):
		var event := SocialEvent.new()
		event.from_dict(event_data as Dictionary)
		if event.id.is_empty() or _by_event_id.has(event.id):
			continue
		events.append(event)
		_by_event_id[event.id] = event
	_start_tick = int(data.get("start_tick", _start_tick))
	_last_tick = int(data.get("last_tick", _last_tick))
	_current_day = maxi(int(data.get("current_day", _current_day)), 1)
	_next_event_id = int(data.get("next_event_id", _next_event_id))
	interaction_radius = float(data.get("interaction_radius", interaction_radius))
	cooldown_ticks = int(data.get("cooldown_ticks", cooldown_ticks))
	event_log_limit = maxi(int(data.get("event_log_limit", event_log_limit)), 1)
	daily_gain_cap = maxi(int(data.get("daily_gain_cap", daily_gain_cap)), 1)
	dropped_event_count = int(data.get("dropped_event_count", dropped_event_count))
	_initialized = bool(data.get("initialized", _initialized))
	# References must survive a load: anything pointing at an inhabitant that is
	# not there is dropped here, instead of being shown to the player later.
	_apply_daily_gain_cap()
	var known := _known_ids()
	graph.remove_orphans(known)
	_drop_dangling_memories()
	_drop_dangling_events(known)


## Human readable problems. An empty array means the social state is consistent.
func validate() -> PackedStringArray:
	var known := _known_ids()
	var problems := graph.validate(known)
	problems.append_array(memory_book.validate(known))
	for event in events:
		if not event.is_valid():
			problems.append("event '%s' is invalid" % event.id)
			continue
		for actor_id in event.actor_ids:
			if not known.has(actor_id):
				problems.append("event '%s' refers to unknown '%s'" % [event.id, actor_id])
	if events.size() > event_log_limit:
		problems.append(
			"event log holds %d entries, the limit is %d" % [events.size(), event_log_limit]
		)
	return problems


func summary() -> String:
	return "%d relazioni, %d ricordi, %d eventi registrati" % [
		graph.count(), memory_book.total_count(), events.size()
	]


# --- internals ---------------------------------------------------------------


func _known_ids() -> Dictionary:
	var known: Dictionary = {}
	if _npc_system == null:
		return known
	for record in _npc_system.get_records():
		known[record.id] = true
	return known


func _drop_dangling_memories() -> void:
	var known := _known_ids()
	if known.is_empty():
		return
	memory_book.remove_orphans(known)


## Drops events naming an inhabitant the world no longer has. Called when a
## snapshot is loaded: an event about a stranger cannot be shown to the player,
## and keeping it would leave a reference nothing can resolve.
func _drop_dangling_events(known: Dictionary) -> void:
	if known.is_empty():
		return
	var removed := 0
	for index in range(events.size() - 1, -1, -1):
		var event := events[index]
		var dangling := false
		for actor_id in event.actor_ids:
			if not known.has(actor_id):
				dangling = true
				break
		if dangling:
			events.remove_at(index)
			_by_event_id.erase(event.id)
			removed += 1
	if removed > 0:
		dropped_event_count += removed
		GameLog.warning(
			TAG, "%d eventi eliminati al caricamento: partecipanti sconosciuti." % removed
		)


func _apply_daily_gain_cap() -> void:
	for relationship in graph.all_relationships():
		relationship.daily_gain_cap = daily_gain_cap


## Groups the inhabitants by the place they are at. Members follow the roster
## order and the caller sorts the place ids, so the whole scan is repeatable.
func _place_groups() -> Dictionary:
	var groups: Dictionary = {}
	if _npc_system == null:
		return groups
	for record in _npc_system.get_records():
		if not SocialRules.is_available(record):
			continue
		if record.current_place_id.is_empty():
			continue
		if not groups.has(record.current_place_id):
			var members: Array[NpcRecord] = []
			groups[record.current_place_id] = members
		(groups[record.current_place_id] as Array[NpcRecord]).append(record)
	return groups


func _run_interactions(tick: int) -> void:
	if _npc_system == null:
		return
	var registry := _npc_system.get_place_registry()
	if registry == null:
		return
	var minute_of_day := posmod(tick, SimulationClock.MINUTES_PER_DAY)
	var groups := _place_groups()
	var place_ids: Array = groups.keys()
	place_ids.sort()
	var busy: Dictionary = {}
	var produced := 0
	for place_id in place_ids:
		if produced >= SocialRules.MAX_INTERACTIONS_PER_TICK:
			break
		var place := registry.get_place(String(place_id))
		if place == null:
			continue
		var members := groups[place_id] as Array[NpcRecord]
		for first_index in members.size():
			for second_index in range(first_index + 1, members.size()):
				if produced >= SocialRules.MAX_INTERACTIONS_PER_TICK:
					break
				var first := members[first_index]
				var second := members[second_index]
				if busy.has(first.id) or busy.has(second.id):
					continue
				if not _pair_is_ready(first, second, tick):
					continue
				if _attempt_interaction(first, second, place, tick, minute_of_day):
					busy[first.id] = true
					busy[second.id] = true
					produced += 1


## Proximity plus the pair cooldown. Both conditions are explicit: an
## interaction never happens just because the code iterated over that pair.
func _pair_is_ready(first: NpcRecord, second: NpcRecord, tick: int) -> bool:
	if first.position.distance_to(second.position) > interaction_radius:
		return false
	var relationship := graph.get_relationship(first.id, second.id)
	if relationship == null or relationship.last_interaction_tick < 0:
		return true
	return tick - relationship.last_interaction_tick >= cooldown_ticks


func _attempt_interaction(
	first: NpcRecord, second: NpcRecord, place: NpcPlace, tick: int, minute_of_day: int
) -> bool:
	var kind := SocialRules.decide_interaction(
		first, second, place, minute_of_day, graph, _economy
	)
	if kind == SocialRules.KIND_NONE:
		return false
	var interaction := SocialInteraction.new()
	# Canonical order: the lower id proposes, the other one answers. Fixed, so
	# the same world never replays the same scene with swapped roles.
	interaction.left = first if first.id <= second.id else second
	interaction.right = second if first.id <= second.id else first
	interaction.place = place
	interaction.tick = tick
	interaction.kind = kind
	var relationship := graph.ensure(interaction.left.id, interaction.right.id, "primo incontro")
	if relationship == null:
		return false
	match kind:
		SocialEvent.Kind.DISAGREEMENT:
			_apply_disagreement(interaction)
		SocialEvent.Kind.HELP:
			_apply_help(interaction)
		SocialEvent.Kind.COOPERATION:
			_apply_cooperation(interaction)
		SocialEvent.Kind.CONVERSATION:
			_apply_conversation(interaction)
		_:
			_apply_greeting(interaction)
	_record(interaction, relationship)
	return true


func _day_index_of(tick: int) -> int:
	return tick / SimulationClock.MINUTES_PER_DAY


func _apply_greeting(interaction: SocialInteraction) -> void:
	var relationship := graph.get_relationship(interaction.left.id, interaction.right.id)
	var day_index := _day_index_of(interaction.tick)
	interaction.effects["familiarity"] = relationship.gain_familiarity(
		SocialRules.GREETING_FAMILIARITY, day_index
	)
	interaction.effects["affinity_%s" % interaction.left.id] = relationship.gain_affinity(
		interaction.left.id, SocialRules.GREETING_AFFINITY, day_index
	)
	interaction.effects["affinity_%s" % interaction.right.id] = relationship.gain_affinity(
		interaction.right.id, SocialRules.GREETING_AFFINITY, day_index
	)
	interaction.outcome = SocialEvent.Outcome.NEUTRAL
	interaction.initiator = interaction.left
	interaction.reason = "saluto"
	interaction.role_left = NpcMemory.ROLE_SHARED
	interaction.role_right = NpcMemory.ROLE_SHARED
	interaction.importance_left = SocialRules.GREETING_IMPORTANCE
	interaction.importance_right = SocialRules.GREETING_IMPORTANCE


func _apply_conversation(interaction: SocialInteraction) -> void:
	var relationship := graph.get_relationship(interaction.left.id, interaction.right.id)
	var day_index := _day_index_of(interaction.tick)
	interaction.effects["familiarity"] = relationship.gain_familiarity(
		SocialRules.CONVERSATION_FAMILIARITY, day_index
	)
	interaction.effects["trust_%s" % interaction.left.id] = relationship.gain_trust(
		interaction.left.id, SocialRules.CONVERSATION_TRUST, day_index
	)
	interaction.effects["trust_%s" % interaction.right.id] = relationship.gain_trust(
		interaction.right.id, SocialRules.CONVERSATION_TRUST, day_index
	)
	interaction.effects["affinity_%s" % interaction.left.id] = relationship.gain_affinity(
		interaction.left.id, SocialRules.CONVERSATION_AFFINITY, day_index
	)
	interaction.effects["affinity_%s" % interaction.right.id] = relationship.gain_affinity(
		interaction.right.id, SocialRules.CONVERSATION_AFFINITY, day_index
	)
	_shift_wellbeing(interaction.left, SocialRules.CONVERSATION_WELLBEING)
	_shift_wellbeing(interaction.right, SocialRules.CONVERSATION_WELLBEING)
	interaction.outcome = SocialEvent.Outcome.POSITIVE
	interaction.initiator = interaction.left
	interaction.reason = "conversazione"
	interaction.importance_left = SocialRules.CONVERSATION_IMPORTANCE
	interaction.importance_right = SocialRules.CONVERSATION_IMPORTANCE


func _apply_cooperation(interaction: SocialInteraction) -> void:
	var relationship := graph.get_relationship(interaction.left.id, interaction.right.id)
	var day_index := _day_index_of(interaction.tick)
	# `left` proposes, `right` decides, using what `right` remembers of `left`.
	interaction.willingness = SocialRules.cooperation_willingness(
		interaction.right.id,
		interaction.left.id,
		graph,
		memory_book,
		1 + day_index
	)
	interaction.accepted = interaction.willingness >= SocialRules.COOPERATION_WILLINGNESS_THRESHOLD
	interaction.initiator = interaction.left
	interaction.role_left = NpcMemory.ROLE_STARTED
	if interaction.accepted:
		interaction.effects["familiarity"] = relationship.gain_familiarity(
			SocialRules.COOPERATION_FAMILIARITY, day_index
		)
		interaction.effects["trust_%s" % interaction.left.id] = relationship.gain_trust(
			interaction.left.id, SocialRules.COOPERATION_TRUST, day_index
		)
		interaction.effects["trust_%s" % interaction.right.id] = relationship.gain_trust(
			interaction.right.id, SocialRules.COOPERATION_TRUST, day_index
		)
		interaction.effects["affinity_%s" % interaction.left.id] = relationship.gain_affinity(
			interaction.left.id, SocialRules.COOPERATION_AFFINITY, day_index
		)
		interaction.effects["affinity_%s" % interaction.right.id] = relationship.gain_affinity(
			interaction.right.id, SocialRules.COOPERATION_AFFINITY, day_index
		)
		_shift_wellbeing(interaction.left, SocialRules.COOPERATION_WELLBEING)
		_shift_wellbeing(interaction.right, SocialRules.COOPERATION_WELLBEING)
		interaction.outcome = SocialEvent.Outcome.POSITIVE
		interaction.role_right = NpcMemory.ROLE_SHARED
		interaction.reason = "cooperazione accettata"
	else:
		interaction.effects["tension"] = relationship.shift_tension(
			SocialRules.COOPERATION_REFUSED_TENSION
		)
		interaction.effects["affinity_%s" % interaction.right.id] = -relationship.lose_affinity(
			interaction.right.id, SocialRules.COOPERATION_REFUSED_AFFINITY
		)
		interaction.outcome = SocialEvent.Outcome.REFUSED
		interaction.role_right = NpcMemory.ROLE_DECLINED
		interaction.reason = "cooperazione rifiutata"
	interaction.importance_left = SocialRules.base_importance(
		SocialEvent.Kind.COOPERATION, interaction.accepted
	)
	interaction.importance_right = interaction.importance_left


func _apply_help(interaction: SocialInteraction) -> void:
	var relationship := graph.get_relationship(interaction.left.id, interaction.right.id)
	var day_index := _day_index_of(interaction.tick)
	# The receiver is the one who is short of food; `help_conditions` already
	# checked that exactly one of the two qualifies.
	if SocialRules.needs_help(interaction.left):
		interaction.receiver = interaction.left
		interaction.giver = interaction.right
	else:
		interaction.receiver = interaction.right
		interaction.giver = interaction.left
	interaction.effects["familiarity"] = relationship.gain_familiarity(
		SocialRules.HELP_FAMILIARITY, day_index
	)
	interaction.effects["trust_%s" % interaction.receiver.id] = relationship.gain_trust(
		interaction.receiver.id, SocialRules.HELP_TRUST, day_index
	)
	interaction.effects["affinity_%s" % interaction.receiver.id] = relationship.gain_affinity(
		interaction.receiver.id, SocialRules.HELP_AFFINITY, day_index
	)
	interaction.effects["affinity_%s" % interaction.giver.id] = relationship.gain_affinity(
		interaction.giver.id, SocialRules.HELP_AFFINITY, day_index
	)
	_shift_wellbeing(interaction.receiver, SocialRules.HELP_WELLBEING_RECEIVED)
	_shift_wellbeing(interaction.giver, SocialRules.HELP_WELLBEING_GIVEN)
	interaction.outcome = SocialEvent.Outcome.POSITIVE
	interaction.initiator = interaction.giver
	interaction.reason = "aiuto"
	interaction.role_left = (
		NpcMemory.ROLE_RECEIVED if interaction.left == interaction.receiver else NpcMemory.ROLE_GIVEN
	)
	interaction.role_right = (
		NpcMemory.ROLE_RECEIVED if interaction.right == interaction.receiver else NpcMemory.ROLE_GIVEN
	)
	# The receiver remembers it more strongly than the giver: the same event,
	# two memories with different weight. That difference is the point.
	interaction.importance_left = (
		SocialRules.HELP_IMPORTANCE
		if interaction.left == interaction.receiver
		else SocialRules.HELP_GIVER_IMPORTANCE
	)
	interaction.importance_right = (
		SocialRules.HELP_IMPORTANCE
		if interaction.right == interaction.receiver
		else SocialRules.HELP_GIVER_IMPORTANCE
	)


func _apply_disagreement(interaction: SocialInteraction) -> void:
	var relationship := graph.get_relationship(interaction.left.id, interaction.right.id)
	interaction.effects["tension"] = relationship.shift_tension(SocialRules.DISAGREEMENT_TENSION)
	interaction.effects["trust_%s" % interaction.left.id] = -relationship.lose_trust(
		interaction.left.id, SocialRules.DISAGREEMENT_TRUST
	)
	interaction.effects["trust_%s" % interaction.right.id] = -relationship.lose_trust(
		interaction.right.id, SocialRules.DISAGREEMENT_TRUST
	)
	interaction.effects["affinity_%s" % interaction.left.id] = -relationship.lose_affinity(
		interaction.left.id, SocialRules.DISAGREEMENT_AFFINITY
	)
	interaction.effects["affinity_%s" % interaction.right.id] = -relationship.lose_affinity(
		interaction.right.id, SocialRules.DISAGREEMENT_AFFINITY
	)
	_shift_wellbeing(interaction.left, SocialRules.DISAGREEMENT_WELLBEING)
	_shift_wellbeing(interaction.right, SocialRules.DISAGREEMENT_WELLBEING)
	interaction.outcome = SocialEvent.Outcome.NEGATIVE
	interaction.initiator = interaction.left
	interaction.reason = "disaccordo"
	interaction.importance_left = SocialRules.DISAGREEMENT_IMPORTANCE
	interaction.importance_right = SocialRules.DISAGREEMENT_IMPORTANCE


## The common tail of every interaction: stamp the relationship, write the
## objective event, store one memory per participant.
func _record(interaction: SocialInteraction, relationship: SocialRelationship) -> void:
	if not interaction.is_complete():
		push_error("SocialSystem: refusing to record an incomplete interaction.")
		return
	var event := SocialEvent.new()
	event.id = _next_event_key()
	event.kind = interaction.kind
	event.outcome = interaction.outcome
	event.tick = interaction.tick
	event.day = 1 + _day_index_of(interaction.tick)
	event.minute_of_day = posmod(interaction.tick, SimulationClock.MINUTES_PER_DAY)
	event.place_id = interaction.place.id
	event.place_name = interaction.place.display_name
	event.actor_ids = PackedStringArray([interaction.left.id, interaction.right.id])
	event.actor_ids.sort()
	event.initiator_id = interaction.initiator.id if interaction.initiator != null else ""
	event.summary = SocialRules.describe_event(
		interaction.kind,
		interaction.giver if interaction.giver != null else interaction.left,
		interaction.receiver if interaction.receiver != null else interaction.right,
		interaction.place,
		interaction.accepted
	)
	var is_first_meeting := relationship.interaction_count == 0
	event.importance = SocialRules.importance_for(
		interaction.kind, is_first_meeting, interaction.accepted
	)
	event.effects = interaction.effects.duplicate()
	_add_event(event)
	_remember(interaction, interaction.left, event)
	_remember(interaction, interaction.right, event)
	relationship.interaction_count += 1
	relationship.last_interaction_tick = interaction.tick
	relationship.last_change_tick = interaction.tick
	relationship.last_change_event_id = event.id
	relationship.last_change_reason = interaction.reason


func _remember(interaction: SocialInteraction, owner: NpcRecord, event: SocialEvent) -> void:
	var other := interaction.other_of(owner)
	if other == null:
		return
	var memory := NpcMemory.new()
	memory.owner_id = owner.id
	memory.kind = _memory_kind_for(event.kind)
	memory.event_id = event.id
	memory.tick = event.tick
	memory.day = event.day
	memory.other_ids = PackedStringArray([other.id])
	memory.place_id = event.place_id
	memory.outcome = event.outcome
	memory.role = interaction.role_of(owner)
	memory.summary = SocialRules.describe_memory(
		event.kind, other, interaction.place, memory.role, interaction.accepted
	)
	memory.importance = clampi(
		interaction.importance_of(owner), NpcMemory.IMPORTANCE_MIN, NpcMemory.IMPORTANCE_MAX
	)
	memory.source = NpcMemory.SOURCE_DIRECT
	memory.certainty = NpcMemory.CERTAINTY_WITNESSED
	memory_book.remember(memory)


static func _memory_kind_for(kind: int) -> int:
	match kind:
		SocialEvent.Kind.GREETING:
			return NpcMemory.Kind.GREETING
		SocialEvent.Kind.CONVERSATION:
			return NpcMemory.Kind.CONVERSATION
		SocialEvent.Kind.COOPERATION:
			return NpcMemory.Kind.COOPERATION
		SocialEvent.Kind.HELP:
			return NpcMemory.Kind.HELP
		SocialEvent.Kind.DISAGREEMENT:
			return NpcMemory.Kind.DISAGREEMENT
	return NpcMemory.Kind.ORIGIN


func _next_event_key() -> String:
	var event_id := "evt_%06d" % _next_event_id
	_next_event_id += 1
	return event_id


## Appends an event and keeps the log inside [member event_log_limit]. The
## weakest event leaves first; dropping an important one is counted and logged,
## because a chronicle that loses its best entries without saying so is worse
## than a shorter one.
func _add_event(event: SocialEvent) -> void:
	events.append(event)
	_by_event_id[event.id] = event
	while events.size() > event_log_limit:
		var victim_index := 0
		for index in events.size():
			if events[index].importance < events[victim_index].importance:
				victim_index = index
			elif events[index].importance == events[victim_index].importance \
					and events[index].tick < events[victim_index].tick:
				victim_index = index
		var victim := events[victim_index]
		events.remove_at(victim_index)
		_by_event_id.erase(victim.id)
		dropped_event_count += 1
		if victim.importance >= EVENT_LOG_PROTECT_IMPORTANCE:
			GameLog.warning(
				TAG,
				"registro eventi pieno (%d): rimosso '%s' (importanza %d)"
				% [event_log_limit, victim.summary, victim.importance]
			)


## A social interaction has a real cost in mood: this is the only write this
## system performs on an inhabitant, and it is always clamped.
func _shift_wellbeing(record: NpcRecord, amount: float) -> void:
	record.needs.wellbeing += amount
	record.needs.clamp_all()
