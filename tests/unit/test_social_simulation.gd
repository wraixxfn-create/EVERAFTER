class_name TestSocialSimulation
extends RefCounted
## The social layer running: which interactions happen, why, what they change,
## what they make the characters remember, and whether the same world replayed
## produces the same story.
##
## Every scenario here is a *condition*, not a dice roll: two inhabitants are
## put in a place with a defined activity and the rules are expected to answer
## in one way only. A test that could only pass by luck would not verify the
## requirement it claims to verify.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("SocialSimulation")
	_test_no_interaction_without_context(harness)
	_test_greeting(harness)
	_test_conversation_is_remembered(harness)
	_test_pair_cooldown(harness)
	_test_memory_decides_cooperation(harness)
	_test_help(harness)
	_test_disagreement(harness)
	_test_repeated_events_are_bounded(harness)
	_test_memory_limits_under_load(harness)
	_test_determinism(harness)
	_test_save_and_load(harness)
	_test_load_drops_unknown_references(harness)


# --- fixtures ---------------------------------------------------------------


static func _build_context(population: int, village_food: int) -> Dictionary:
	var registry := NpcPlaceRegistry.new()
	var square := registry.add("square", "Piazza", NpcPlace.Kind.SOCIAL, Vector2(0, 0))
	var inn := registry.add(
		"work_inn", "Locanda", NpcPlace.Kind.FOOD, Vector2(12, 0), 480, 1380, true
	)
	var fields := registry.add(
		"work_field", "Campi", NpcPlace.Kind.WORK, Vector2(24, 0), 390, 780
	)
	var records := NpcRoster.build(population)
	var npc_system := NpcSimulationSystem.new(records, registry, null)
	var economy := EconomySystem.new(npc_system, village_food, 12, 10, 60)
	economy.initialize(0)
	var social := SocialSystem.new(npc_system, economy)
	social.configure(24, 12, 160, 3.2, 45, 14)
	social.initialize(0)
	# The roster seeds a starting web; these scenarios need a clean slate.
	social.graph.clear()
	social.memory_book.clear()
	return {
		"registry": registry,
		"records": records,
		"npc": npc_system,
		"economy": economy,
		"social": social,
		"square": square,
		"inn": inn,
		"fields": fields,
	}


static func _seat(record: NpcRecord, place: NpcPlace, activity: int) -> void:
	record.current_place_id = place.id
	record.current_place_name = place.display_name
	record.position = place.position
	record.destination = place.position
	record.has_destination = false
	record.path = PackedVector2Array()
	record.set_activity(activity, 0)


static func _clock(tick: int) -> SimulationClock:
	var clock := SimulationClock.new()
	clock.tick = tick
	return clock


static func _advance(context: Dictionary, from_tick: int, ticks: int) -> void:
	var social: SocialSystem = context["social"]
	for offset in ticks:
		var tick := from_tick + offset
		social.on_tick(tick, _clock(tick))


# --- scenarios --------------------------------------------------------------


static func _test_no_interaction_without_context(harness: TestHarness) -> void:
	var context := _build_context(4, 24)
	var records: Array[NpcRecord] = context["records"]
	_seat(records[0], context["square"], NpcRecord.Activity.SOCIALIZING)
	_seat(records[1], context["inn"], NpcRecord.Activity.EATING)
	_seat(records[2], context["square"], NpcRecord.Activity.SLEEPING)
	_advance(context, 600, 20)
	var social: SocialSystem = context["social"]
	harness.check_equals(
		social.get_event_count(), 0,
		"nobody interacts when the two are in different places or asleep"
	)
	harness.check_equals(social.memory_book.total_count(), 0, "no event means no memory")


static func _test_greeting(harness: TestHarness) -> void:
	var context := _build_context(4, 24)
	var records: Array[NpcRecord] = context["records"]
	var social: SocialSystem = context["social"]
	_seat(records[0], context["square"], NpcRecord.Activity.SOCIALIZING)
	_seat(records[1], context["square"], NpcRecord.Activity.SOCIALIZING)
	_advance(context, 600, 1)

	harness.check_equals(social.get_event_count(), 1, "one meeting produces one event")
	var event := social.get_events(1)[0]
	harness.check_equals(event.kind, SocialEvent.Kind.GREETING, "strangers greet each other")
	harness.check_equals(
		event.actor_ids, PackedStringArray(["npc_001", "npc_002"]),
		"the event names exactly the two inhabitants involved"
	)
	harness.check_equals(event.day, 1, "the event carries the simulated day")
	harness.check_equals(event.minute_of_day, 600, "the event carries the simulated minute")
	harness.check_equals(event.place_id, "square", "the event carries the place")
	harness.check(event.summary.contains(records[0].display_name), "the summary names a participant")
	harness.check(event.summary.contains(records[1].display_name), "the summary names the other one")

	var relationship := social.graph.get_relationship("npc_001", "npc_002")
	harness.check(relationship != null, "the meeting created a relationship")
	harness.check(relationship.familiarity > 0, "a greeting raises familiarity")
	harness.check_equals(relationship.interaction_count, 1, "the interaction is counted once")
	harness.check_equals(relationship.last_change_event_id, event.id,
		"the relationship points at the event that changed it")

	# A greeting is real but minor: it is written in the event log and it moves
	# the relationship, yet it is below the importance floor, so it is *not*
	# kept as a memory. Keeping every small talk forever is exactly what the
	# memory limit exists to prevent.
	harness.check_equals(social.get_memory_count("npc_001"), 0, "a greeting is not worth a memory")
	harness.check(social.memory_book.rejected_count > 0, "the refusal to remember it is counted")
	harness.check_equals(
		social.memory_lines("npc_001", 1)[0], "Nessun ricordo rilevante.",
		"the panel says so instead of inventing a memory"
	)

	var lines := social.relationship_lines("npc_001", 3)
	harness.check(lines[0].contains(records[1].display_name), "the panel line names the other one")
	harness.check(lines[0].contains("fiducia"), "the panel line explains the value")
	var change := social.change_explanation("npc_001")
	harness.check(change.contains("saluto"), "the panel can say why the value changed")
	harness.check(change.contains("giorno 1"), "the explanation names the day of the event")
	harness.check(social.validate().is_empty(), "the social state is consistent")


static func _test_conversation_is_remembered(harness: TestHarness) -> void:
	var context := _build_context(4, 24)
	var records: Array[NpcRecord] = context["records"]
	var social: SocialSystem = context["social"]
	# They already know each other, so the meeting is a conversation, which is
	# above the importance floor and therefore remembered.
	social.graph.ensure("npc_001", "npc_002", "test").familiarity = 30
	_seat(records[0], context["square"], NpcRecord.Activity.SOCIALIZING)
	_seat(records[1], context["square"], NpcRecord.Activity.SOCIALIZING)
	_advance(context, 600, 1)

	harness.check_equals(social.get_event_count(), 1, "the conversation produced one event")
	var event := social.get_events(1)[0]
	harness.check_equals(event.kind, SocialEvent.Kind.CONVERSATION, "two acquaintances talk")
	harness.check_equals(social.get_memory_count("npc_001"), 1, "each participant remembers it")
	harness.check_equals(social.get_memory_count("npc_002"), 1, "both remember the same event")
	var memory := social.memory_book.memories_of("npc_001")[0]
	harness.check_equals(memory.event_id, event.id, "the memory references its event")
	harness.check(social.get_event(memory.event_id) != null, "the reference resolves")
	harness.check_equals(
		memory.other_ids, PackedStringArray(["npc_002"]), "the memory names the other participant"
	)
	harness.check_equals(memory.owner_id, "npc_001", "the memory belongs to one character")
	harness.check_equals(memory.kind, NpcMemory.Kind.CONVERSATION, "the memory keeps the event type")
	harness.check_equals(memory.day, 1, "the memory keeps the simulated day")
	harness.check_equals(
		social.memory_book.memories_of("npc_003").size(), 0,
		"somebody who was not there remembers nothing"
	)
	var memory_line := social.memory_lines("npc_001", 1)[0]
	harness.check(memory_line.contains("conversazione"), "the memory line describes the event")
	harness.check(memory_line.contains("Giorno 1"), "the memory line names its day")


static func _test_pair_cooldown(harness: TestHarness) -> void:
	var context := _build_context(2, 24)
	var records: Array[NpcRecord] = context["records"]
	var social: SocialSystem = context["social"]
	_seat(records[0], context["square"], NpcRecord.Activity.SOCIALIZING)
	_seat(records[1], context["square"], NpcRecord.Activity.SOCIALIZING)
	_advance(context, 600, 1)
	harness.check_equals(social.get_event_count(), 1, "the first meeting is recorded")
	_advance(context, 601, 40)
	harness.check_equals(
		social.get_event_count(), 1,
		"the same pair does not interact again before the cooldown ends"
	)
	_advance(context, 641, 10)
	harness.check_equals(
		social.get_event_count(), 2, "the pair meets again once the cooldown is over"
	)


static func _test_memory_decides_cooperation(harness: TestHarness) -> void:
	var context := _build_context(4, 24)
	var records: Array[NpcRecord] = context["records"]
	var social: SocialSystem = context["social"]
	var relationship := social.graph.ensure("npc_001", "npc_002", "test")
	relationship.trust_a = 60
	relationship.trust_b = 60
	relationship.affinity_a = 50
	relationship.affinity_b = 50

	# `npc_001` proposes, `npc_002` decides. With these numbers and no history the
	# willingness is exactly 54: one point below the threshold.
	harness.check_equals(
		social.cooperation_willingness("npc_002", "npc_001"), 54,
		"willingness is computed from the documented rule"
	)
	harness.check(
		not SocialRules.would_cooperate(
			"npc_002", "npc_001", social.graph, social.memory_book, 1
		),
		"a character with no history at all declines"
	)

	for record in [records[0], records[1]]:
		record.work_place_id = "work_field"
		record.work_start_minute = 390
		record.work_end_minute = 780
		_seat(record, context["fields"], NpcRecord.Activity.WORKING)
	var trust_before := relationship.trust_of("npc_001")
	var tension_before := relationship.tension
	_advance(context, 600, 1)
	harness.check_equals(social.get_event_count(), 1, "the proposal produced an event")
	var refused := social.get_events(1)[0]
	harness.check_equals(refused.kind, SocialEvent.Kind.COOPERATION, "the event is a cooperation")
	harness.check_equals(refused.outcome, SocialEvent.Outcome.REFUSED, "and it was refused")
	harness.check(
		relationship.tension > tension_before, "a refusal raises the tension between the two"
	)
	harness.check_equals(
		relationship.trust_of("npc_001"), trust_before, "a refusal does not build trust"
	)
	harness.check(
		refused.summary.contains("non ha voluto lavorare"),
		"the event says who declined, in plain words"
	)

	# Now give the deciding character a memory: help received from the proposer.
	# Same relationship numbers, different history, different decision.
	var willingness_before := social.cooperation_willingness("npc_002", "npc_001")
	var help := NpcMemory.new()
	help.owner_id = "npc_002"
	help.kind = NpcMemory.Kind.HELP
	help.role = NpcMemory.ROLE_RECEIVED
	help.other_ids = PackedStringArray(["npc_001"])
	help.summary = "Ha ricevuto del cibo da %s." % records[0].display_name
	help.importance = SocialRules.HELP_IMPORTANCE
	help.day = 1
	help.tick = 500
	harness.check(social.memory_book.remember(help), "the memory is stored")
	harness.check_equals(
		social.cooperation_willingness("npc_002", "npc_001"),
		willingness_before + SocialRules.COOPERATION_HELP_MEMORY_BONUS,
		"the memory of a help received raises the willingness by the documented bonus"
	)

	relationship.last_interaction_tick = -1
	var wellbeing_before := records[1].needs.wellbeing
	_advance(context, 700, 1)
	harness.check_equals(social.get_event_count(), 2, "the second proposal produced an event")
	var accepted := social.get_events(1)[0]
	harness.check_equals(accepted.outcome, SocialEvent.Outcome.POSITIVE, "this time it is accepted")
	harness.check(
		relationship.trust_of("npc_001") > trust_before,
		"an accepted cooperation raises trust"
	)
	harness.check(
		relationship.trust_of("npc_001") <= trust_before + SocialRules.COOPERATION_TRUST,
		"and never more than the documented step"
	)
	harness.check_almost(
		records[1].needs.wellbeing,
		wellbeing_before + SocialRules.COOPERATION_WELLBEING,
		0.0001,
		"cooperating has a measurable effect on the simulation state"
	)

	# A recent argument with the same person cancels the goodwill again.
	var willingness_after_help := social.cooperation_willingness("npc_002", "npc_001")
	var argument := NpcMemory.new()
	argument.owner_id = "npc_002"
	argument.kind = NpcMemory.Kind.DISAGREEMENT
	argument.other_ids = PackedStringArray(["npc_001"])
	argument.summary = "Litigio con %s." % records[0].display_name
	argument.importance = SocialRules.DISAGREEMENT_IMPORTANCE
	argument.day = 1
	argument.tick = 690
	social.memory_book.remember(argument)
	harness.check_equals(
		social.cooperation_willingness("npc_002", "npc_001"),
		willingness_after_help - SocialRules.COOPERATION_ARGUMENT_PENALTY,
		"a recent argument lowers the willingness again"
	)
	harness.check(
		not SocialRules.would_cooperate(
			"npc_002", "npc_001", social.graph, social.memory_book, 1
		),
		"and the same character declines again"
	)


static func _test_help(harness: TestHarness) -> void:
	var context := _build_context(4, 24)
	var records: Array[NpcRecord] = context["records"]
	var social: SocialSystem = context["social"]
	var hungry: NpcRecord = records[0]
	var fed: NpcRecord = records[1]
	hungry.needs.hunger = 85.0
	hungry.needs.energy = 60.0
	hungry.last_meal_satisfied = false
	fed.needs.hunger = 30.0
	fed.needs.energy = 70.0
	_seat(hungry, context["inn"], NpcRecord.Activity.EATING)
	_seat(fed, context["inn"], NpcRecord.Activity.EATING)
	var wellbeing_received := hungry.needs.wellbeing
	var wellbeing_given := fed.needs.wellbeing
	_advance(context, 600, 1)

	harness.check_equals(social.get_event_count(), 1, "the situation produced one event")
	var event := social.get_events(1)[0]
	harness.check_equals(event.kind, SocialEvent.Kind.HELP, "somebody helped somebody else")
	harness.check_equals(event.initiator_id, fed.id, "the event names who gave the help")
	harness.check_equals(event.outcome, SocialEvent.Outcome.POSITIVE, "the help was accepted")
	harness.check(
		event.importance >= SocialRules.HELP_IMPORTANCE,
		"help is an important event (importance %d)" % event.importance
	)

	var relationship := social.graph.get_relationship(hungry.id, fed.id)
	harness.check(relationship != null, "the help created a relationship")
	harness.check(
		relationship.trust_of(hungry.id) > 0,
		"the person who received help now trusts the other"
	)
	harness.check_equals(
		relationship.trust_of(fed.id), 0,
		"the helper's own trust is unchanged: only the receiver's moves"
	)
	harness.check_almost(
		hungry.needs.wellbeing,
		wellbeing_received + SocialRules.HELP_WELLBEING_RECEIVED,
		0.0001,
		"being helped changes the simulation state"
	)
	harness.check_almost(
		fed.needs.wellbeing,
		wellbeing_given + SocialRules.HELP_WELLBEING_GIVEN,
		0.0001,
		"helping has a smaller effect on the helper"
	)

	# The same event, two memories with different weight: the point of keeping
	# the event and the memory apart.
	var received := social.memory_book.memories_of(hungry.id)[0]
	var given := social.memory_book.memories_of(fed.id)[0]
	harness.check_equals(received.role, NpcMemory.ROLE_RECEIVED, "the receiver knows their role")
	harness.check_equals(given.role, NpcMemory.ROLE_GIVEN, "the giver knows theirs")
	harness.check_equals(received.event_id, event.id, "both memories point at the same event")
	harness.check_equals(given.event_id, event.id, "the reference is shared")
	harness.check_equals(received.importance, SocialRules.HELP_IMPORTANCE,
		"the receiver weighs it more")
	harness.check_equals(given.importance, SocialRules.HELP_GIVER_IMPORTANCE,
		"the giver weighs it less")
	harness.check(received.summary.contains("ricevuto"), "the receiver's memory says so")
	harness.check(given.summary.contains("condiviso"), "the giver's memory says so")
	harness.check_equals(received.source, NpcMemory.SOURCE_DIRECT,
		"the memory declares how the character knows it")


static func _test_disagreement(harness: TestHarness) -> void:
	# Village food at zero: the documented shortage condition is met.
	var context := _build_context(4, 0)
	var records: Array[NpcRecord] = context["records"]
	var social: SocialSystem = context["social"]
	var economy: EconomySystem = context["economy"]
	harness.check(economy.has_shortage(ResourceType.FOOD), "the fixture really has a shortage")

	var first: NpcRecord = records[0]
	var second: NpcRecord = records[1]
	first.personality.calmness = 50
	second.personality.calmness = 50
	first.needs.hunger = 80.0
	second.needs.hunger = 40.0
	first.work_place_id = "work_field"
	second.work_place_id = "work_field"
	_seat(first, context["fields"], NpcRecord.Activity.WORKING)
	_seat(second, context["fields"], NpcRecord.Activity.WORKING)
	var wellbeing_first := first.needs.wellbeing
	_advance(context, 600, 1)

	harness.check_equals(social.get_event_count(), 1, "the shortage produced one event")
	var event := social.get_events(1)[0]
	harness.check_equals(event.kind, SocialEvent.Kind.DISAGREEMENT, "and it is a disagreement")
	harness.check_equals(event.outcome, SocialEvent.Outcome.NEGATIVE, "recorded as negative")
	harness.check(event.summary.contains("scarseggiano"), "the summary names the cause")

	var relationship := social.graph.get_relationship(first.id, second.id)
	harness.check_equals(
		relationship.tension, SocialRules.DISAGREEMENT_TENSION, "the tension is the documented step"
	)
	harness.check(relationship.trust_of(first.id) == 0, "trust starts at zero and cannot go below")
	harness.check_almost(
		first.needs.wellbeing,
		wellbeing_first + SocialRules.DISAGREEMENT_WELLBEING,
		0.0001,
		"an argument costs both characters some wellbeing"
	)
	var memory := social.memory_book.memories_of(first.id)[0]
	harness.check_equals(memory.kind, NpcMemory.Kind.DISAGREEMENT, "the argument is remembered")
	harness.check(memory.importance >= NpcMemory.PERMANENT_IMPORTANCE - 10,
		"an argument is a memory that resists being forgotten")

	# Without the shortage the same two characters simply cooperate instead.
	var calm := _build_context(4, 24)
	var calm_records: Array[NpcRecord] = calm["records"]
	calm_records[0].personality.calmness = 50
	calm_records[1].personality.calmness = 50
	calm_records[0].needs.hunger = 80.0
	calm_records[0].work_place_id = "work_field"
	calm_records[1].work_place_id = "work_field"
	_seat(calm_records[0], calm["fields"], NpcRecord.Activity.WORKING)
	_seat(calm_records[1], calm["fields"], NpcRecord.Activity.WORKING)
	_advance(calm, 600, 1)
	var calm_social: SocialSystem = calm["social"]
	harness.check_equals(calm_social.get_event_count(), 1, "the well fed pair also interacts")
	harness.check_equals(
		calm_social.get_events(1)[0].kind, SocialEvent.Kind.COOPERATION,
		"without the shortage the same context produces cooperation, not conflict"
	)


static func _test_repeated_events_are_bounded(harness: TestHarness) -> void:
	var context := _build_context(2, 24)
	var records: Array[NpcRecord] = context["records"]
	var social: SocialSystem = context["social"]
	social.cooldown_ticks = 0
	_seat(records[0], context["square"], NpcRecord.Activity.SOCIALIZING)
	_seat(records[1], context["square"], NpcRecord.Activity.SOCIALIZING)

	_advance(context, 1, 300)
	var relationship := social.graph.get_relationship("npc_001", "npc_002")
	harness.check(relationship != null, "the pair keeps meeting")
	harness.check(
		relationship.interaction_count > 100,
		"they really did meet many times (%d)" % relationship.interaction_count
	)
	harness.check(
		relationship.familiarity <= SocialRelationship.VALUE_MAX,
		"familiarity never leaves its range"
	)
	harness.check(
		relationship.positive_gain_today <= social.daily_gain_cap,
		"one day of constant contact cannot give more than the daily cap"
	)
	var first_day := relationship.familiarity
	_advance(context, SimulationClock.MINUTES_PER_DAY + 1, 300)
	harness.check(
		relationship.positive_gain_today <= social.daily_gain_cap,
		"the cap is applied again on the second day"
	)
	harness.check(
		relationship.familiarity > first_day,
		"a new day still allows some growth (not a frozen relationship)"
	)
	harness.check(
		relationship.familiarity <= SocialRelationship.VALUE_MAX,
		"and it still never crosses the ceiling"
	)
	# Six more days of non-stop greetings: the curve must flatten, not explode.
	var before_last_day := relationship.familiarity
	_advance(context, 2 * SimulationClock.MINUTES_PER_DAY, 6 * 1440)
	harness.check(
		relationship.familiarity <= SocialRelationship.VALUE_MAX,
		"after a week of greetings the value is still inside the range"
	)
	harness.check(
		relationship.familiarity - before_last_day <= social.daily_gain_cap * 6,
		"six days of growth are bounded by six daily caps"
	)
	harness.check_equals(
		social.memory_book.count_of("npc_001") <= social.memory_book.capacity_per_npc,
		true,
		"a week of meetings does not overflow the memory book"
	)


static func _test_memory_limits_under_load(harness: TestHarness) -> void:
	var context := _build_context(2, 24)
	var records: Array[NpcRecord] = context["records"]
	var social: SocialSystem = context["social"]
	# Small on purpose: capacity 4 memories, 40 events in the log, no cooldown.
	social.configure(4, 12, 40, 3.2, 0, 14)
	# Acquaintances, so every meeting is a conversation: important enough to be
	# remembered, and therefore enough to fill the book.
	social.graph.ensure("npc_001", "npc_002", "test").familiarity = 30
	_seat(records[0], context["square"], NpcRecord.Activity.SOCIALIZING)
	_seat(records[1], context["square"], NpcRecord.Activity.SOCIALIZING)
	_advance(context, 1, 300)

	harness.check(
		social.memory_book.count_of("npc_001") <= 4, "the memory book respects its capacity"
	)
	harness.check(social.memory_book.evicted_count > 0, "surplus memories were evicted")
	harness.check_equals(
		social.memory_book.evicted_protected_count, 0,
		"greetings are minor: no important memory was dropped"
	)
	harness.check(social.get_event_count() <= 40, "the event log respects its limit")
	harness.check(social.dropped_event_count > 0, "the oldest weak events left the log")
	harness.check_equals(
		social.memory_book.validate().size(), 0, "the book is still consistent"
	)
	harness.check_equals(social.validate().size(), 0, "the whole social state is consistent")
	for memory in social.memory_book.memories_of("npc_001"):
		if memory.event_id.is_empty():
			continue
		harness.check(
			social.get_event(memory.event_id) != null or memory.importance < 50,
			"a memory whose event left the log is a minor one"
		)


static func _test_determinism(harness: TestHarness) -> void:
	var first := _build_context(6, 24)
	var second := _build_context(6, 24)
	for context in [first, second]:
		var records: Array[NpcRecord] = context["records"]
		_seat(records[0], context["square"], NpcRecord.Activity.SOCIALIZING)
		_seat(records[1], context["square"], NpcRecord.Activity.SOCIALIZING)
		_seat(records[2], context["inn"], NpcRecord.Activity.EATING)
		_seat(records[3], context["inn"], NpcRecord.Activity.EATING)
		records[2].needs.hunger = 84.0
		records[2].last_meal_satisfied = false
		records[4].work_place_id = "work_field"
		records[5].work_place_id = "work_field"
		_seat(records[4], context["fields"], NpcRecord.Activity.WORKING)
		_seat(records[5], context["fields"], NpcRecord.Activity.WORKING)
	_advance(first, 500, 400)
	_advance(second, 500, 400)
	var first_social: SocialSystem = first["social"]
	var second_social: SocialSystem = second["social"]
	harness.check(first_social.get_event_count() > 0, "the scenario really produced events")
	harness.check_equals(
		first_social.get_event_count(), second_social.get_event_count(),
		"the same world produces the same number of events"
	)
	harness.check_equals(
		str(first_social.to_dict()), str(second_social.to_dict()),
		"the same world produces the same social state"
	)


static func _test_save_and_load(harness: TestHarness) -> void:
	var context := _build_context(4, 24)
	var records: Array[NpcRecord] = context["records"]
	var social: SocialSystem = context["social"]
	_seat(records[0], context["inn"], NpcRecord.Activity.EATING)
	_seat(records[1], context["inn"], NpcRecord.Activity.EATING)
	_seat(records[2], context["square"], NpcRecord.Activity.SOCIALIZING)
	_seat(records[3], context["square"], NpcRecord.Activity.SOCIALIZING)
	records[0].needs.hunger = 86.0
	records[0].last_meal_satisfied = false
	_advance(context, 600, 200)
	harness.check(social.get_event_count() > 0, "there is something to save")

	var snapshot := social.to_dict()
	var loaded := SocialSystem.new(context["npc"], context["economy"])
	loaded.from_dict(snapshot)
	harness.check_equals(
		loaded.get_relationship_count(), social.get_relationship_count(),
		"relationships survive a save"
	)
	harness.check_equals(
		loaded.get_event_count(), social.get_event_count(), "events survive a save"
	)
	harness.check_equals(
		loaded.memory_book.total_count(), social.memory_book.total_count(),
		"memories survive a save"
	)
	harness.check_equals(loaded.get_last_tick(), social.get_last_tick(), "the tick survives")
	var original := social.graph.get_relationship("npc_001", "npc_002")
	var restored := loaded.graph.get_relationship("npc_001", "npc_002")
	harness.check(restored != null, "a saved relationship can be found again")
	harness.check_equals(restored.familiarity, original.familiarity, "its values are intact")
	harness.check_equals(restored.trust_a, original.trust_a, "directional trust is intact")
	harness.check_equals(
		restored.last_change_event_id, original.last_change_event_id, "the event link is intact"
	)
	harness.check_equals(
		loaded.validate().size(), 0, "a loaded social state passes its own validation"
	)
	var unresolved := 0
	for owner_id in loaded.memory_book.owner_ids():
		for memory in loaded.memory_book.memories_of(owner_id):
			if memory.event_id.is_empty():
				continue
			if loaded.get_event(memory.event_id) == null:
				unresolved += 1
	harness.check_equals(unresolved, 0, "every loaded memory still points at its event")
	harness.check_equals(
		str(loaded.to_dict()), str(social.to_dict()), "saving again produces the same snapshot"
	)


static func _test_load_drops_unknown_references(harness: TestHarness) -> void:
	# Save a world of six inhabitants, load it into a world of two: everything
	# pointing at somebody who is no longer there must go, not stay dangling.
	var big := _build_context(6, 24)
	var big_records: Array[NpcRecord] = big["records"]
	_seat(big_records[0], big["square"], NpcRecord.Activity.SOCIALIZING)
	_seat(big_records[4], big["square"], NpcRecord.Activity.SOCIALIZING)
	_advance(big, 600, 120)
	var big_social: SocialSystem = big["social"]
	harness.check(big_social.get_event_count() > 0, "the bigger world produced events")
	harness.check(big_social.get_relationship_count() > 0, "and it has relationships")

	var small := _build_context(2, 24)
	var small_social: SocialSystem = small["social"]
	small_social.from_dict(big_social.to_dict())
	var known := {"npc_001": true, "npc_002": true}
	for relationship in small_social.graph.all_relationships():
		harness.check(
			known.has(relationship.a_id) and known.has(relationship.b_id),
			"no loaded relationship points outside the population"
		)
	for owner_id in small_social.memory_book.owner_ids():
		harness.check(known.has(owner_id), "no loaded memory belongs to a stranger")
		for memory in small_social.memory_book.memories_of(owner_id):
			for other_id in memory.other_ids:
				harness.check(known.has(other_id), "no loaded memory names a stranger")
	harness.check_equals(
		small_social.validate().size(), 0,
		"the reduced world validates cleanly after loading"
	)
