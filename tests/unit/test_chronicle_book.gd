class_name TestChronicleBook
extends RefCounted
## Unit tests for `ChronicleBook` and `ChronicleEntry`.

static func run_tests(h: TestHarness) -> void:
	h.suite("ChronicleBook")

	var book := ChronicleBook.new(12)

	# Recording ignores entries below the importance floor.
	h.check(book.record(ChronicleEntry.Category.PRODUCTION, 1, 0, 0, 3, "nope") == null,
		"entries below importance floor are ignored")
	h.check(book.count() == 0, "book stays empty on ignored entries")

	# Recording a valid entry.
	var e := book.record(ChronicleEntry.Category.MILESTONE, 1, 0, 0, 40, "inizio")
	h.check(e != null, "valid entry is recorded")
	h.check(book.count() == 1, "count reflects one entry")
	h.check(book.get_entry(e.id) == e, "get_entry returns the same entry")
	h.check(e.is_valid(), "entry is_valid()")
	h.check(e.id.begins_with("chr_"), "entry id uses chr_ prefix")

	# Duplicate ids are impossible when using record().
	var e2 := book.record(ChronicleEntry.Category.PRODUCTION, 2, 30, 1500, 30, "raccolto")
	h.check(e2.id != e.id, "ids are unique")

	# Query filters.
	book.record(ChronicleEntry.Category.SHORTAGE, 2, 120, 1560, 80, "fame")
	var q_day := book.query(0, 2)
	h.check_equals(q_day.size(), 2, "query by day returns both entries on day 2")
	var q_cat := book.query(0, 0, ChronicleEntry.Category.MILESTONE)
	h.check_equals(q_cat.size(), 1, "query by category returns only the milestone")
	var q_imp := book.query(60)
	h.check_equals(q_imp.size(), 1, "query by importance filters low-importance entries")

	# Eviction policy: adding entries past the cap evicts non-landmarks.
	for i in 20:
		book.record(ChronicleEntry.Category.MILESTONE, 3, i, 1440 + i, 10 + (i % 30), "voce %d" % i)
	# Cap is 12, book was at 3, so after 20 more it is trimmed to 12.
	h.check(book.count() <= 12, "capacity is enforced (cap 12)")
	# The high-importance SHORTAGE entry (importance 80, a landmark) must
	# still be there.
	var found_fame := false
	for ent in book.get_entries():
		if ent.summary == "fame":
			found_fame = true
			break
	h.check(found_fame, "landmark entry survives eviction when any non-landmark exists")

	# Serialization round-trip.
	var data := book.to_dict()
	var book2 := ChronicleBook.new()
	book2.from_dict(data)
	h.check_equals(book2.count(), book.count(), "round trip preserves entry count")
	h.check_equals(book2.last_day(), book.last_day(), "round trip preserves last day")
	# The first entry's summary matches.
	var e_again := book2.get_entry(e.id)
	h.check(e_again != null, "entry id preserved through round trip")
	h.check(e_again.summary == e.summary, "entry summary preserved through round trip")

	# Subject orphan removal drops entries that reference a missing npc.
	book2.record(ChronicleEntry.Category.HELP, 4, 0, 4 * 1440, 50, "aiuto tra amici", ["npc_001", "npc_002"])
	book2.record(ChronicleEntry.Category.RELATIONSHIP, 4, 10, 4 * 1440 + 10, 40, "litigio", ["npc_003"])
	var before := book2.count()
	book2.remove_subject_orphans({"npc_001": true})
	# Both new entries reference missing NPCs (npc_002 and npc_003) so both
	# are removed.
	h.check(book2.count() == before - 2, "orphan subjects are removed")

	# Clear resets the book.
	book2.clear()
	h.check_equals(book2.count(), 0, "clear empties the book")
	h.check_equals(book2.evicted_count, 0, "clear resets evicted counters")

	# from_dict of invalid data does not crash or insert garbage.
	var book3 := ChronicleBook.new()
	book3.from_dict({"entries": [{"id": "", "summary": "bad"}, {"not": "a real entry"}]})
	h.check_equals(book3.count(), 0, "invalid entries are ignored on load")

	# ChronicleEntry serialization round-trip.
	var entry := ChronicleEntry.new()
	entry.id = "chr_test"
	entry.day = 3
	entry.minute_of_day = 420
	entry.category = ChronicleEntry.Category.HELP
	entry.subject_ids = PackedStringArray(["npc_001", "npc_002"])
	entry.resource_ids = PackedStringArray([ResourceType.FOOD])
	entry.summary = "Una mano tesa."
	entry.importance = 60
	entry.details = {"amount": 2}
	var d := entry.to_dict()
	var restored := ChronicleEntry.new()
	restored.from_dict(d)
	h.check_equals(restored.id, "chr_test", "entry id round trip")
	h.check_equals(restored.day, 3, "entry day round trip")
	h.check_equals(restored.minute_of_day, 420, "entry minute round trip")
	h.check_equals(restored.summary, "Una mano tesa.", "entry summary round trip")
	h.check_equals(restored.importance, 60, "entry importance round trip")
	h.check(restored.is_valid(), "restored entry is valid")
