class_name TestSocialRelationships
extends RefCounted
## The social data layer: identity of a relationship, its value ranges, the
## brakes on repeated interactions, the memory book limits and serialisation.
## No simulation runs here, so every expectation is an exact number.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("SocialRelationships")
	_test_identity(harness)
	_test_shared_and_directional(harness)
	_test_diminishing_returns(harness)
	_test_daily_cap(harness)
	_test_orphans_and_validation(harness)
	_test_graph_round_trip(harness)
	_test_memory_book_limits(harness)
	_test_memory_round_trip(harness)
	_test_event_and_memory_data(harness)


static func _test_identity(harness: TestHarness) -> void:
	harness.check_equals(
		SocialRelationship.canonical_key("npc_002", "npc_001"),
		"npc_001|npc_002",
		"the key is built in canonical order"
	)
	harness.check_equals(
		SocialRelationship.canonical_key("npc_001", "npc_002"),
		SocialRelationship.canonical_key("npc_002", "npc_001"),
		"the key does not depend on the order of the arguments"
	)
	var graph := RelationshipGraph.new()
	var created := graph.create("npc_002", "npc_001", "amico")
	harness.check(created != null, "a valid pair creates a relationship")
	harness.check_equals(created.a_id, "npc_001", "the smaller id becomes a_id")
	harness.check_equals(created.b_id, "npc_002", "the larger id becomes b_id")
	harness.check_equals(created.key(), SocialRelationship.canonical_key("npc_001", "npc_002"),
		"the instance key matches the canonical key")
	harness.check(graph.create("npc_001", "npc_002") == null, "the same pair cannot be created twice")
	harness.check_equals(graph.count(), 1, "a refused duplicate adds nothing to the graph")
	harness.check(graph.create("npc_001", "npc_001") == null, "a self relationship is refused")
	harness.check(graph.create("", "npc_002") == null, "an empty id is refused")
	harness.check_equals(
		graph.get_relationship("npc_002", "npc_001"), created, "lookup ignores the order"
	)
	harness.check(graph.has_relationship("npc_001", "npc_002"), "the pair is registered both ways")
	harness.check_equals(created.other_id("npc_001"), "npc_002", "the partner of A is B")
	harness.check_equals(
		created.other_id("npc_999"), "", "an id outside the pair has no partner"
	)
	harness.check_equals(graph.partner_ids_of("npc_001").size(), 1, "one partner is indexed")
	harness.check_equals(graph.partner_ids_of("npc_999").size(), 0, "a stranger has no partner")
	harness.check(graph.ensure("npc_002", "npc_001") == created, "ensure returns the existing pair")
	harness.check(graph.ensure("npc_001", "npc_003") != null, "ensure creates a missing pair")
	harness.check_equals(graph.count(), 2, "ensure created exactly one new relationship")
	harness.check(graph.remove("npc_003", "npc_001"), "a relationship can be removed")
	harness.check(not graph.remove("npc_003", "npc_001"), "removing it twice does nothing")


static func _test_shared_and_directional(harness: TestHarness) -> void:
	# The daily cap is deliberately out of the way here (it has its own test):
	# this one is about *who* a value belongs to, not about how fast it grows.
	var relationship := SocialRelationship.new("npc_001", "npc_002")
	relationship.daily_gain_cap = 100
	harness.check_equals(
		relationship.gain_trust("npc_001", 10, 0), 10, "trust grows while there is room"
	)
	harness.check_equals(relationship.trust_a, 10, "the gain landed on the asked side")
	harness.check_equals(relationship.trust_b, 0, "the other side is untouched: trust is directional")
	harness.check_equals(
		relationship.gain_affinity("npc_002", 8, 0), 8, "affinity grows on its own side"
	)
	harness.check_equals(relationship.affinity_a, 0, "affinity is directional too")
	harness.check_equals(relationship.affinity_b, 8, "the gain landed on the second side")

	var shared := SocialRelationship.new("npc_001", "npc_002")
	shared.daily_gain_cap = 100
	shared.gain_familiarity(20, 0)
	harness.check_equals(shared.familiarity, 20, "familiarity is a single shared value")
	shared.shift_tension(15)
	harness.check_equals(shared.tension, 15, "tension is a single shared value")
	harness.check_equals(shared.shift_tension(-40), -15, "tension stops at zero")
	harness.check_equals(shared.tension, 0, "tension never goes below the range")

	var clamped := SocialRelationship.new("npc_001", "npc_002")
	clamped.trust_a = 400
	clamped.affinity_b = -30
	clamped.clamp_all()
	harness.check_equals(clamped.trust_a, 100, "a value above the range is clamped")
	harness.check_equals(clamped.affinity_b, 0, "a value below the range is clamped")
	harness.check_equals(clamped.trust_of("npc_999"), 0, "reading an outsider returns the minimum")
	harness.check_equals(clamped.gain_trust("npc_999", 10, 0), 0, "an outsider cannot gain trust")
	harness.check_equals(clamped.lose_trust("npc_999", 10), 0, "an outsider cannot lose trust")
	harness.check(clamped.is_valid(), "a clamped relationship is valid")
	var broken := SocialRelationship.new("npc_001", "npc_001")
	harness.check(not broken.is_valid(), "a self relationship is not valid")


static func _test_diminishing_returns(harness: TestHarness) -> void:
	harness.check_equals(
		SocialRelationship.scaled_gain(0, 10), 10, "a full step at the bottom of the range"
	)
	harness.check_equals(
		SocialRelationship.scaled_gain(50, 10), 5, "half a step halfway up"
	)
	harness.check_equals(
		SocialRelationship.scaled_gain(90, 10), 1, "almost nothing near the ceiling"
	)
	harness.check_equals(
		SocialRelationship.scaled_gain(100, 10), 0, "nothing at all at the ceiling"
	)
	harness.check_equals(
		SocialRelationship.scaled_gain(10, -5), 0, "a negative step grants nothing"
	)

	var relationship := SocialRelationship.new("npc_001", "npc_002")
	relationship.daily_gain_cap = 1000
	for index in 400:
		relationship.gain_familiarity(SocialRules.GREETING_FAMILIARITY, index / 20)
	harness.check(
		relationship.familiarity <= SocialRelationship.VALUE_MAX,
		"hundreds of greetings never cross the ceiling"
	)
	harness.check(
		relationship.familiarity > 90,
		"repeated greetings still build a strong familiarity (got %d)" % relationship.familiarity
	)
	harness.check_equals(
		relationship.strength(), relationship.familiarity,
		"with no trust and no affinity the strength is the familiarity alone"
	)
	var bonded := SocialRelationship.new("npc_001", "npc_002")
	bonded.familiarity = 30
	bonded.trust_a = 40
	bonded.trust_b = 20
	bonded.affinity_a = 10
	bonded.affinity_b = 5
	bonded.tension = 4
	harness.check_equals(
		bonded.strength(), 30 + 20 + 5 - 8,
		"the strength counts the weaker side of the pair and weighs tension double"
	)


static func _test_daily_cap(harness: TestHarness) -> void:
	var relationship := SocialRelationship.new("npc_001", "npc_002")
	relationship.daily_gain_cap = 5
	harness.check_equals(
		relationship.gain_trust("npc_001", 10, 0), 5, "a gain is cut down to the daily cap"
	)
	harness.check_equals(
		relationship.gain_trust("npc_001", 10, 0), 0, "a second gain the same day grants nothing"
	)
	harness.check_equals(relationship.positive_room(0), 0, "the day has nothing left to give")
	harness.check_equals(relationship.positive_room(1), 5, "a new day resets the allowance")
	harness.check(
		relationship.gain_trust("npc_001", 10, 1) > 0, "the next day allows new gains again"
	)
	harness.check_equals(relationship.lose_trust("npc_001", 3), 3, "damage is never capped")


static func _test_orphans_and_validation(harness: TestHarness) -> void:
	var graph := RelationshipGraph.new()
	graph.create("npc_001", "npc_002")
	graph.create("npc_002", "npc_003")
	graph.create("npc_003", "npc_004")
	var known := {"npc_001": true, "npc_002": true, "npc_003": true}
	harness.check_equals(
		graph.validate(known).size(), 1, "a relationship with an unknown inhabitant is reported"
	)
	harness.check_equals(graph.remove_orphans(known), 1, "the orphan relationship is removed")
	harness.check_equals(graph.count(), 2, "the valid relationships stay")
	harness.check_equals(graph.validate(known).size(), 0, "the graph is consistent again")
	harness.check_equals(graph.validate().size(), 0, "validation without a roster finds nothing")


static func _test_graph_round_trip(harness: TestHarness) -> void:
	var graph := RelationshipGraph.new()
	var relationship := graph.create("npc_001", "npc_002", "amico")
	relationship.familiarity = 42
	relationship.trust_a = 31
	relationship.trust_b = 27
	relationship.affinity_a = 55
	relationship.tension = 7
	relationship.interaction_count = 3
	relationship.last_interaction_tick = 120
	relationship.last_change_event_id = "evt_000001"
	relationship.last_change_reason = "aiuto"

	var restored := RelationshipGraph.new()
	restored.from_dict(graph.to_dict())
	harness.check_equals(restored.count(), 1, "the graph survives a round-trip")
	var copy := restored.get_relationship("npc_002", "npc_001")
	harness.check(copy != null, "the pair can be found after loading")
	harness.check(copy != relationship, "the loaded relationship is a separate object")
	harness.check_equals(copy.familiarity, 42, "shared familiarity survives")
	harness.check_equals(copy.trust_a, 31, "directional trust survives")
	harness.check_equals(copy.trust_b, 27, "the other direction survives, unchanged")
	harness.check_equals(copy.tension, 7, "shared tension survives")
	harness.check_equals(copy.interaction_count, 3, "the interaction count survives")
	harness.check_equals(copy.last_change_event_id, "evt_000001", "the event reference survives")
	harness.check_equals(copy.last_change_reason, "aiuto", "the reason survives")

	# A save file that somehow holds the same pair twice must not create two bonds.
	var data := graph.to_dict()
	var entries: Array = data["relationships"]
	entries.append(entries[0])
	var twice := RelationshipGraph.new()
	twice.from_dict(data)
	harness.check_equals(twice.count(), 1, "a duplicated pair in a save is ignored")
	harness.check_equals(
		twice.validate({"npc_001": true, "npc_002": true}).size(), 0,
		"the deduplicated graph is consistent"
	)


static func _test_memory_book_limits(harness: TestHarness) -> void:
	var book := MemoryBook.new()
	book.configure(3, 10)
	var minor := NpcMemory.new()
	minor.owner_id = "npc_001"
	minor.summary = "Un saluto di poco conto."
	minor.importance = 5
	minor.day = 1
	harness.check(not book.remember(minor), "a memory below the importance floor is refused")
	harness.check_equals(book.rejected_count, 1, "the refusal is counted")
	harness.check_equals(book.count_of("npc_001"), 0, "a refused memory is not stored")

	var stored: Array[NpcMemory] = []
	for index in 5:
		var memory := NpcMemory.new()
		memory.owner_id = "npc_001"
		memory.summary = "Ricordo %d." % index
		memory.importance = 20 + index
		memory.day = index + 1
		memory.tick = (index + 1) * 100
		harness.check(book.remember(memory), "a memory above the floor is stored")
		stored.append(memory)
	harness.check_equals(book.count_of("npc_001"), 3, "the configured capacity is enforced")
	harness.check_equals(book.evicted_count, 2, "the surplus left the book")
	harness.check_equals(book.evicted_protected_count, 0, "no important memory was dropped yet")
	harness.check(book.find_memory(stored[0].id) == null, "the weakest memory was evicted")
	harness.check(book.find_memory(stored[4].id) != null, "the most important one is still there")
	harness.check(book.find_memory(stored[0].id) == null, "an evicted id cannot be found")
	var ids := {}
	for memory in book.memories_of("npc_001"):
		harness.check(not ids.has(memory.id), "memory ids are unique")
		ids[memory.id] = true
	harness.check_equals(book.validate().size(), 0, "the book is consistent")

	# Protected memories are only dropped when nothing else can go.
	var guarded := MemoryBook.new()
	guarded.configure(2, 0)
	var weak := _memory_for("npc_002", "Una chiacchiera.", 30, 1)
	var strong := _memory_for("npc_002", "Un soccorso.", 90, 1)
	var medium := _memory_for("npc_002", "Un litigio.", 80, 1)
	var extra := _memory_for("npc_002", "Una reconciliazione.", 85, 1)
	guarded.remember(weak)
	guarded.remember(strong)
	guarded.remember(medium)
	harness.check_equals(guarded.count_of("npc_002"), 2, "the capacity holds")
	harness.check(guarded.find_memory(weak.id) == null, "the unprotected memory left first")
	harness.check_equals(guarded.evicted_protected_count, 0, "nothing important was dropped")
	guarded.remember(extra)
	harness.check_equals(guarded.count_of("npc_002"), 2, "the capacity holds again")
	harness.check_equals(
		guarded.evicted_protected_count, 1, "dropping an important memory is counted"
	)
	harness.check(guarded.find_memory(strong.id) != null, "the strongest memory survives")

	# Orphans: an unknown owner or an unknown participant is dropped.
	var orphan_book := MemoryBook.new()
	orphan_book.configure(10, 0)
	orphan_book.remember(_memory_for("npc_001", "Un ricordo valido.", 50, 1))
	orphan_book.remember(_memory_for("npc_777", "Un ricordo di nessuno.", 50, 1))
	var dangling := _memory_for("npc_001", "Con uno sconosciuto.", 50, 1)
	dangling.other_ids = PackedStringArray(["npc_888"])
	orphan_book.remember(dangling)
	harness.check_equals(
		orphan_book.remove_orphans({"npc_001": true}), 2, "dangling memories are removed"
	)
	harness.check_equals(orphan_book.count_of("npc_001"), 1, "the valid memory stays")
	harness.check_equals(orphan_book.total_count(), 1, "the book only holds known inhabitants")


static func _test_memory_round_trip(harness: TestHarness) -> void:
	var book := MemoryBook.new()
	book.configure(8, 10)
	var memory := _memory_for("npc_001", "Ha ricevuto del cibo da Mira.", 58, 3)
	memory.kind = NpcMemory.Kind.HELP
	memory.role = NpcMemory.ROLE_RECEIVED
	memory.event_id = "evt_000007"
	memory.other_ids = PackedStringArray(["npc_002"])
	memory.place_id = "work_inn"
	memory.certainty = 100
	book.remember(memory)
	var restored := MemoryBook.new()
	restored.from_dict(book.to_dict())
	harness.check_equals(restored.count_of("npc_001"), 1, "memories survive a round-trip")
	harness.check_equals(restored.capacity_per_npc, 8, "the capacity survives a round-trip")
	var copy := restored.find_memory(memory.id)
	harness.check(copy != null, "the memory can be found by id after loading")
	harness.check_equals(copy.event_id, "evt_000007", "the reference to the event survives")
	harness.check_equals(copy.role, NpcMemory.ROLE_RECEIVED, "the role survives")
	harness.check_equals(copy.other_ids, PackedStringArray(["npc_002"]), "the participants survive")
	harness.check_equals(copy.importance, 58, "the importance survives")
	harness.check_equals(restored.validate().size(), 0, "the loaded book is consistent")


static func _test_event_and_memory_data(harness: TestHarness) -> void:
	var event := SocialEvent.new()
	event.id = "evt_000001"
	event.kind = SocialEvent.Kind.HELP
	event.outcome = SocialEvent.Outcome.POSITIVE
	event.tick = 600
	event.day = 1
	event.minute_of_day = 600
	event.actor_ids = PackedStringArray(["npc_002", "npc_001"])
	event.summary = "Mira ha condiviso il cibo con Elio."
	event.importance = 58
	event.place_id = "work_inn"
	harness.check(event.is_valid(), "a complete event is valid")
	harness.check(event.involves("npc_001"), "the event lists its participants")
	harness.check(not event.involves("npc_999"), "the event does not invent participants")
	harness.check_equals(event.kind_label(), "aiuto", "the kind has a readable label")
	harness.check_equals(
		event.actors_text({"npc_001": "Elio", "npc_002": "Mira"}), "Mira, Elio",
		"the actors are rendered in the stored order"
	)
	harness.check(event.is_significant(50), "an important event is significant")
	harness.check(not event.is_significant(70), "the significance threshold is honoured")

	var restored := SocialEvent.new()
	restored.from_dict(event.to_dict())
	harness.check_equals(restored.id, event.id, "the event id survives a round-trip")
	harness.check_equals(restored.actor_ids, event.actor_ids, "the participants survive")
	harness.check_equals(restored.importance, 58, "the importance survives")
	harness.check_equals(restored.kind, SocialEvent.Kind.HELP, "the kind survives")
	harness.check(restored.is_valid(), "the loaded event is valid")

	var incomplete := SocialEvent.new()
	incomplete.id = "evt_000002"
	harness.check(not incomplete.is_valid(), "an event without participants is not valid")

	var memory := _memory_for("npc_001", "Ha ricevuto del cibo.", 58, 1)
	harness.check(memory.involves("npc_001"), "the owner is always involved in their memory")
	harness.check(not memory.involves("npc_002"), "somebody else is not involved by default")
	harness.check_equals(memory.age_in_days(4), 3, "the age of a memory is measured in days")
	harness.check_equals(memory.age_in_days(0), 0, "a memory is never negative in age")
	harness.check(
		memory.retention_score(1) > memory.retention_score(6),
		"a memory loses weight as it gets older"
	)
	harness.check(not memory.is_protected(), "an ordinary memory is not protected")
	var heavy := _memory_for("npc_001", "Un soccorso.", 90, 1)
	harness.check(heavy.is_protected(), "a strong memory is protected")
	harness.check_equals(NpcMemory.SOURCE_DIRECT, "diretto", "the perspective source is explicit")


static func _memory_for(
	owner_id: String, summary: String, importance: int, day: int
) -> NpcMemory:
	var memory := NpcMemory.new()
	memory.owner_id = owner_id
	memory.summary = summary
	memory.importance = importance
	memory.day = day
	memory.tick = (day - 1) * SimulationClock.MINUTES_PER_DAY + 100
	return memory
