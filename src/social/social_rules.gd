class_name SocialRules
extends RefCounted
## The whole social rule set, in one readable and testable place.
##
## Everything here is a pure function or a constant. Nothing reads the clock,
## the scene tree, a node or `randf()`: given the same two records, the same
## place, the same minute and the same relationship, these functions always
## return the same answer, which is what makes the social layer verifiable.
##
## ## What can happen
## Five interactions, chosen by context and never at random
## ([method decide_interaction] evaluates them in a fixed priority order):
##
## * `DISAGREEMENT` — same workplace, both working, food shortage in the
##   village, at least one of them hungry, average calmness below 70.
##   Effects: tension `+14`, trust `-6`, affinity `-7`, wellbeing `-2,0`.
## * `HELP` — a place that serves food, one of the two without a ration or very
##   hungry, the other fed and with food actually available. Effects: trust of
##   the receiver `+9`, affinity `+6`, wellbeing `+2,5` / `+0,5`.
## * `COOPERATION` — both working in the same place. Accepted: familiarity `+5`,
##   trust `+5`, affinity `+4`, wellbeing `+0,8`. Refused: tension `+8`.
## * `CONVERSATION` — same social place, familiarity >= 20. Effects: familiarity
##   `+4`, trust `+2`, affinity `+4`, wellbeing `+0,3`.
## * `GREETING` — same social place, familiarity < 20. Effects: familiarity
##   `+6`, affinity `+2`.
##
## Every positive step then passes through `SocialRelationship`, which applies
## diminishing returns and the daily cap, so the numbers above are ceilings and
## not guarantees: a hundred greetings in a day do not produce a hundred times
## the friendship of one.
##
## ## Consequences that reach the simulation
## A cooperation is only accepted when [method cooperation_willingness] reaches
## [constant COOPERATION_WILLINGNESS_THRESHOLD]. That value is computed from the
## relationship *and* from the memories the character holds, so an important
## memory (help received, a recent argument) changes what the character does
## next, not only what the panel says.

## Nobody interacts from farther away than this, in world units.
const PROXIMITY_RADIUS := 3.2
## Minimum ticks between two interactions of the same pair.
const COOLDOWN_TICKS := 45
## Ceiling of interactions produced in a single tick, so a crowd cannot make a
## tick expensive or flood the event log.
const MAX_INTERACTIONS_PER_TICK := 2

## --- disagreement ----------------------------------------------------------
const DISAGREEMENT_HUNGER := 72.0
const DISAGREEMENT_MAX_CALMNESS := 70
const DISAGREEMENT_TENSION := 14
const DISAGREEMENT_TRUST := 6
const DISAGREEMENT_AFFINITY := 7
const DISAGREEMENT_WELLBEING := -2.0
const DISAGREEMENT_IMPORTANCE := 66

## --- help ------------------------------------------------------------------
const HELP_NEEDED_HUNGER := 78.0
const HELPER_MAX_HUNGER := 55.0
const HELPER_MIN_ENERGY := 20.0
const HELP_FAMILIARITY := 8
const HELP_TRUST := 9
const HELP_AFFINITY := 6
const HELP_WELLBEING_RECEIVED := 2.5
const HELP_WELLBEING_GIVEN := 0.5
const HELP_IMPORTANCE := 58
const HELP_GIVER_IMPORTANCE := 40

## --- cooperation -----------------------------------------------------------
const COOPERATION_FAMILIARITY := 5
const COOPERATION_TRUST := 5
const COOPERATION_AFFINITY := 4
const COOPERATION_WELLBEING := 0.8
const COOPERATION_IMPORTANCE := 30
const COOPERATION_REFUSED_TENSION := 8
const COOPERATION_REFUSED_AFFINITY := 4
const COOPERATION_REFUSED_IMPORTANCE := 26
## Willingness needed to say yes. `50` is the neutral starting point, so a
## character with no history at all neither accepts nor refuses by default: the
## decision comes from what they remember.
const COOPERATION_WILLINGNESS_THRESHOLD := 55
const COOPERATION_HELP_MEMORY_BONUS := 14
const COOPERATION_ARGUMENT_PENALTY := 18
const COOPERATION_ARGUMENT_DAYS := 3
## Minimum importance for a memory to count in a future decision.
const DECISION_MEMORY_IMPORTANCE := 45

## --- conversation and greeting --------------------------------------------
const CONVERSATION_FAMILIARITY_LIMIT := 20
const CONVERSATION_FAMILIARITY := 4
const CONVERSATION_TRUST := 2
const CONVERSATION_AFFINITY := 4
const CONVERSATION_WELLBEING := 0.3
const CONVERSATION_IMPORTANCE := 12
const GREETING_FAMILIARITY := 6
const GREETING_AFFINITY := 2
const GREETING_IMPORTANCE := 6
## A first meeting matters more than the tenth: this is added when the pair had
## no relationship before the event.
const FIRST_MEETING_IMPORTANCE_BONUS := 10

## Starting values of the relationships seeded from the roster.
const SEED_FAMILY_AFFINITY := 68
const SEED_FAMILY_FAMILIARITY := 85
const SEED_FAMILY_TRUST := 62
const SEED_FRIEND_AFFINITY := 46
const SEED_FRIEND_FAMILIARITY := 58
const SEED_FRIEND_TRUST := 40
const SEED_ACQUAINTANCE_AFFINITY := 18
const SEED_ACQUAINTANCE_FAMILIARITY := 27
const SEED_ACQUAINTANCE_TRUST := 18
const SEED_NEIGHBOUR_AFFINITY := 22
const SEED_NEIGHBOUR_FAMILIARITY := 30
const SEED_NEIGHBOUR_TRUST := 20
const ORIGIN_MEMORY_IMPORTANCE := 40

const KIND_NONE := -1


## True when the inhabitant can take part in an interaction at all. Sleeping,
## blocked and walking characters are busy doing something else.
static func is_available(record: NpcRecord) -> bool:
	if record == null:
		return false
	match record.activity:
		NpcRecord.Activity.SLEEPING, NpcRecord.Activity.BLOCKED, NpcRecord.Activity.WALKING:
			return false
	return true


## The interaction this pair has now, or [constant KIND_NONE]. The order of the
## checks is the priority: an argument about missing food outranks a chat, and
## work comes before small talk because it is what the two are actually doing.
static func decide_interaction(
	first: NpcRecord,
	second: NpcRecord,
	place: NpcPlace,
	minute_of_day: int,
	graph: RelationshipGraph,
	economy: EconomySystem
) -> int:
	if not is_available(first) or not is_available(second) or place == null:
		return KIND_NONE
	if _both_working_together(first, second, place):
		if disagreement_conditions(first, second, economy):
			return SocialEvent.Kind.DISAGREEMENT
		return SocialEvent.Kind.COOPERATION
	if help_conditions(first, second, place, minute_of_day, economy):
		return SocialEvent.Kind.HELP
	if conversation_conditions(first, second, place):
		var relationship := graph.get_relationship(first.id, second.id)
		var familiarity := relationship.familiarity if relationship != null else 0
		if familiarity < CONVERSATION_FAMILIARITY_LIMIT:
			return SocialEvent.Kind.GREETING
		return SocialEvent.Kind.CONVERSATION
	return KIND_NONE


static func _both_working_together(
	first: NpcRecord, second: NpcRecord, place: NpcPlace
) -> bool:
	return (
		first.activity == NpcRecord.Activity.WORKING
		and second.activity == NpcRecord.Activity.WORKING
		and not first.work_place_id.is_empty()
		and first.work_place_id == second.work_place_id
		and first.work_place_id == place.id
	)


## An argument is not bad luck: it needs a defined shortage, somebody actually
## hungry and two people who are not famously patient.
static func disagreement_conditions(
	first: NpcRecord, second: NpcRecord, economy: EconomySystem
) -> bool:
	if economy == null or not economy.has_shortage(ResourceType.FOOD):
		return false
	if first.needs.hunger < DISAGREEMENT_HUNGER and second.needs.hunger < DISAGREEMENT_HUNGER:
		return false
	var average_calmness := (first.personality.calmness + second.personality.calmness) / 2
	return average_calmness < DISAGREEMENT_MAX_CALMNESS


## Somebody is short of food, the other can spare some, and the place is one
## where eating happens. Without a real ration available nobody promises help.
static func help_conditions(
	first: NpcRecord,
	second: NpcRecord,
	place: NpcPlace,
	minute_of_day: int,
	economy: EconomySystem
) -> bool:
	if not (place.is_food_available(minute_of_day) or place.kind == NpcPlace.Kind.HOME):
		return false
	var needy := _needy_of(first, second)
	var helper := second if needy == first else first
	if needy == null or helper == null:
		return false
	if helper.needs.hunger > HELPER_MAX_HUNGER or helper.needs.energy < HELPER_MIN_ENERGY:
		return false
	if economy == null:
		return false
	return EconomyRules.has_available_food_for(economy, helper.id)


## The one who needs help, or `null` when neither qualifies. Checked in a fixed
## order so the same pair always produces the same giver and receiver.
static func _needy_of(first: NpcRecord, second: NpcRecord) -> NpcRecord:
	if needs_help(first):
		return first
	if needs_help(second):
		return second
	return null


## True when this inhabitant is the one who needs help: they went without a
## ration, or their hunger is at the documented threshold.
static func needs_help(record: NpcRecord) -> bool:
	return not record.last_meal_satisfied or record.needs.hunger >= HELP_NEEDED_HUNGER


## Free time in a place where people meet: the only case where talking is the
## activity itself, and not noise added on top of something else.
static func conversation_conditions(
	first: NpcRecord, second: NpcRecord, place: NpcPlace
) -> bool:
	if not (place.is_social_place() or place.is_rest_place()):
		return false
	return _is_leisure(first) and _is_leisure(second)


static func _is_leisure(record: NpcRecord) -> bool:
	match record.activity:
		NpcRecord.Activity.SOCIALIZING, NpcRecord.Activity.EATING, \
				NpcRecord.Activity.RESTING, NpcRecord.Activity.IDLE:
			return true
	return false


## 0..100: how willing [param asker] is to work with [param partner] right now.
##
## The rule is deliberately readable:
## * start from `50` (neutral);
## * move with the relationship: `+0,4` per point of trust above 50, `+0,2` per
##   point of affinity above 50, `-0,6` per point of tension;
## * `+14` when the character remembers being helped by this partner
##   (importance >= 45);
## * `-18` when they remember an argument with this partner in the last
##   `COOPERATION_ARGUMENT_DAYS` days (importance >= 45).
## This is the place where the memory system changes behaviour: the same pair,
## with the same numbers but a different history, answers differently.
static func cooperation_willingness(
	asker_id: String,
	partner_id: String,
	graph: RelationshipGraph,
	book: MemoryBook,
	current_day: int
) -> int:
	var willingness := 50
	var relationship := graph.get_relationship(asker_id, partner_id)
	if relationship != null:
		willingness += int(round((relationship.trust_of(asker_id) - 50) * 0.4))
		willingness += int(round((relationship.affinity_of(asker_id) - 50) * 0.2))
		willingness -= int(round(relationship.tension * 0.6))
	if book != null:
		for memory in book.memories_of(asker_id):
			if memory.importance < DECISION_MEMORY_IMPORTANCE:
				continue
			if not memory.involves(partner_id):
				continue
			if memory.kind == NpcMemory.Kind.HELP and memory.role == NpcMemory.ROLE_RECEIVED:
				willingness += COOPERATION_HELP_MEMORY_BONUS
			elif memory.kind == NpcMemory.Kind.DISAGREEMENT \
					and memory.age_in_days(current_day) <= COOPERATION_ARGUMENT_DAYS:
				willingness -= COOPERATION_ARGUMENT_PENALTY
	return clampi(willingness, 0, 100)


## The decision the memory system feeds: does this character say yes?
static func would_cooperate(
	asker_id: String,
	partner_id: String,
	graph: RelationshipGraph,
	book: MemoryBook,
	current_day: int
) -> bool:
	return cooperation_willingness(asker_id, partner_id, graph, book, current_day) \
		>= COOPERATION_WILLINGNESS_THRESHOLD


## Base importance of an interaction, before the first-meeting bonus.
static func base_importance(kind: int, accepted: bool = true) -> int:
	match kind:
		SocialEvent.Kind.DISAGREEMENT:
			return DISAGREEMENT_IMPORTANCE
		SocialEvent.Kind.HELP:
			return HELP_IMPORTANCE
		SocialEvent.Kind.COOPERATION:
			return COOPERATION_IMPORTANCE if accepted else COOPERATION_REFUSED_IMPORTANCE
		SocialEvent.Kind.CONVERSATION:
			return CONVERSATION_IMPORTANCE
		SocialEvent.Kind.GREETING:
			return GREETING_IMPORTANCE
	return 0


## Importance of the event, including the bonus for a pair that had never met.
static func importance_for(kind: int, is_first_meeting: bool, accepted: bool = true) -> int:
	var importance := base_importance(kind, accepted)
	if is_first_meeting:
		importance += FIRST_MEETING_IMPORTANCE_BONUS
	return clampi(importance, SocialEvent.IMPORTANCE_MIN, SocialEvent.IMPORTANCE_MAX)


static func kind_label(kind: int) -> String:
	match kind:
		SocialEvent.Kind.GREETING:
			return "saluto"
		SocialEvent.Kind.CONVERSATION:
			return "conversazione"
		SocialEvent.Kind.COOPERATION:
			return "cooperazione"
		SocialEvent.Kind.HELP:
			return "aiuto"
		SocialEvent.Kind.DISAGREEMENT:
			return "disaccordo"
	return "incontro"


## Objective one-line description of the event, used by the event log and by the
## future chronicle.
static func describe_event(
	kind: int, first: NpcRecord, second: NpcRecord, place: NpcPlace, accepted: bool
) -> String:
	var where := place.display_name if place != null else "il villaggio"
	match kind:
		SocialEvent.Kind.GREETING:
			return "%s e %s si sono salutati a %s." % [first.display_name, second.display_name, where]
		SocialEvent.Kind.CONVERSATION:
			return "%s e %s hanno parlato a %s." % [first.display_name, second.display_name, where]
		SocialEvent.Kind.COOPERATION:
			if accepted:
				return "%s e %s hanno lavorato insieme a %s." % [
					first.display_name, second.display_name, where
				]
			return "%s non ha voluto lavorare con %s a %s." % [
				second.display_name, first.display_name, where
			]
		SocialEvent.Kind.HELP:
			return "%s ha condiviso il cibo con %s a %s." % [
				first.display_name, second.display_name, where
			]
		SocialEvent.Kind.DISAGREEMENT:
			return "Disaccordo tra %s e %s a %s, con le scorte di cibo che scarseggiano." % [
				first.display_name, second.display_name, where
			]
	return "%s e %s si sono incontrati a %s." % [first.display_name, second.display_name, where]


## What the owner of the memory kept of the event, in one short sentence. The
## wording is the character's own side of the story, not the neutral report.
static func describe_memory(
	kind: int, other: NpcRecord, place: NpcPlace, role: String, accepted: bool
) -> String:
	var where := place.display_name if place != null else "in paese"
	match kind:
		SocialEvent.Kind.GREETING:
			return "Saluto con %s a %s." % [other.display_name, where]
		SocialEvent.Kind.CONVERSATION:
			return "Ha parlato con %s a %s." % [other.display_name, where]
		SocialEvent.Kind.COOPERATION:
			if accepted:
				return "Ha lavorato insieme a %s a %s." % [other.display_name, where]
			if role == NpcMemory.ROLE_DECLINED:
				return "Ha preferito non lavorare con %s a %s." % [other.display_name, where]
			return "%s non ha voluto lavorare insieme a %s." % [other.display_name, where]
		SocialEvent.Kind.HELP:
			if role == NpcMemory.ROLE_RECEIVED:
				return "Ha ricevuto del cibo da %s a %s." % [other.display_name, where]
			return "Ha condiviso il suo cibo con %s a %s." % [other.display_name, where]
		SocialEvent.Kind.DISAGREEMENT:
			return "Litigio con %s a %s per il cibo che mancava." % [other.display_name, where]
	return "Incontro con %s." % other.display_name


## Builds the starting relationship web of a population. Deterministic by
## construction: the same list of records always produces the same graph, and
## every relationship points at two inhabitants of that list.
static func build_initial_relationships(records: Array[NpcRecord]) -> RelationshipGraph:
	var graph := RelationshipGraph.new()
	for first_index in records.size():
		for second_index in range(first_index + 1, records.size()):
			var roll := (first_index + 1) * 37 + (second_index + 1) * 61
			var relationship: SocialRelationship = null
			var origin := ""
			if roll % 11 == 0:
				origin = "familiare"
				relationship = graph.create(
					records[first_index].id, records[second_index].id, origin
				)
				if relationship != null:
					relationship.familiarity = SEED_FAMILY_FAMILIARITY
					relationship.trust_a = SEED_FAMILY_TRUST
					relationship.trust_b = SEED_FAMILY_TRUST
					relationship.affinity_a = SEED_FAMILY_AFFINITY
					relationship.affinity_b = SEED_FAMILY_AFFINITY
			elif roll % 5 == 0:
				origin = "amico"
				relationship = graph.create(
					records[first_index].id, records[second_index].id, origin
				)
				if relationship != null:
					relationship.familiarity = SEED_FRIEND_FAMILIARITY
					relationship.trust_a = SEED_FRIEND_TRUST
					relationship.trust_b = SEED_FRIEND_TRUST
					relationship.affinity_a = SEED_FRIEND_AFFINITY
					relationship.affinity_b = SEED_FRIEND_AFFINITY
			elif roll % 3 == 0:
				origin = "conoscente"
				relationship = graph.create(
					records[first_index].id, records[second_index].id, origin
				)
				if relationship != null:
					relationship.familiarity = SEED_ACQUAINTANCE_FAMILIARITY
					relationship.trust_a = SEED_ACQUAINTANCE_TRUST
					relationship.trust_b = SEED_ACQUAINTANCE_TRUST
					relationship.affinity_a = SEED_ACQUAINTANCE_AFFINITY
					relationship.affinity_b = SEED_ACQUAINTANCE_AFFINITY
	# Nobody starts isolated: an inhabitant without any bond is linked to the
	# next one in the list as a neighbour.
	for index in records.size():
		if not graph.relationships_of(records[index].id).is_empty():
			continue
		if records.size() < 2:
			continue
		var other := records[(index + 1) % records.size()]
		var relationship := graph.create(records[index].id, other.id, "vicino di casa")
		if relationship == null:
			continue
		relationship.familiarity = SEED_NEIGHBOUR_FAMILIARITY
		relationship.trust_a = SEED_NEIGHBOUR_TRUST
		relationship.trust_b = SEED_NEIGHBOUR_TRUST
		relationship.affinity_a = SEED_NEIGHBOUR_AFFINITY
		relationship.affinity_b = SEED_NEIGHBOUR_AFFINITY
	return graph


## Turns the roster background of every inhabitant into one starting memory.
## These memories have no event behind them: they predate the simulation.
static func seed_origin_memories(records: Array[NpcRecord], book: MemoryBook) -> int:
	var stored := 0
	for record in records:
		if record.origin_note.is_empty():
			continue
		var memory := NpcMemory.new()
		memory.owner_id = record.id
		memory.kind = NpcMemory.Kind.ORIGIN
		memory.tick = 0
		memory.day = 1
		memory.other_ids = PackedStringArray()
		memory.summary = record.origin_note
		memory.importance = ORIGIN_MEMORY_IMPORTANCE
		if book.remember(memory):
			stored += 1
	return stored


## The relationships of one inhabitant, strongest first. This is what the panel
## shows, so "le sue relazioni principali" is a rule and not a lucky ordering.
static func strongest_relationships(
	npc_id: String, graph: RelationshipGraph, limit: int
) -> Array[SocialRelationship]:
	var result := graph.relationships_of(npc_id)
	result.sort_custom(_stronger_first)
	if limit >= 0 and result.size() > limit:
		result.resize(maxi(limit, 0))
	return result


static func _stronger_first(
	first: SocialRelationship, second: SocialRelationship
) -> bool:
	var first_score := _strength(first)
	var second_score := _strength(second)
	if first_score != second_score:
		return first_score > second_score
	if first.familiarity != second.familiarity:
		return first.familiarity > second.familiarity
	return first.key() < second.key()


static func _strength(relationship: SocialRelationship) -> int:
	return relationship.strength()
