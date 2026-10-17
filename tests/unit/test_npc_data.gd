class_name TestNpcData
extends RefCounted
## Checks for the pure data layer of the NPC system: needs, personality,
## places, place lookup and record serialisation. No scene, no node, no GPU.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("NpcData")
	_test_needs(harness)
	_test_personality(harness)
	_test_places(harness)
	_test_record(harness)


static func _test_needs(harness: TestHarness) -> void:
	var needs := NpcNeeds.new(120.0, -20.0, 64.0)
	harness.check_almost(needs.energy, 100.0, 0.0001, "energy is clamped high")
	harness.check_almost(needs.hunger, 0.0, 0.0001, "hunger is clamped low")
	needs.energy = -5.0
	needs.hunger = 140.0
	needs.wellbeing = 130.0
	needs.clamp_all()
	harness.check_almost(needs.energy, 0.0, 0.0001, "clamp_all fixes energy")
	harness.check_almost(needs.hunger, 100.0, 0.0001, "clamp_all fixes hunger")
	harness.check_almost(needs.wellbeing, 100.0, 0.0001, "clamp_all fixes wellbeing")
	harness.check(
		needs.get_pressure() >= 0.0 and needs.get_pressure() <= 1.0,
		"pressure is normalised"
	)
	var copy := needs.copy()
	copy.energy = 50.0
	harness.check_almost(needs.energy, 0.0, 0.0001, "copy is independent")
	var restored := NpcNeeds.new()
	restored.from_dict(copy.to_dict())
	harness.check_almost(restored.energy, 50.0, 0.0001, "needs round-trip")


static func _test_personality(harness: TestHarness) -> void:
	var personality := NpcPersonality.new(-10, 50, 120, 70)
	harness.check_equals(personality.diligence, 0, "diligence is clamped")
	harness.check_equals(personality.curiosity, 100, "curiosity is clamped")
	personality.sociability = 999
	personality.clamp_all()
	harness.check_equals(personality.sociability, 100, "clamp_all fixes sociability")
	var copy := personality.copy()
	copy.calmness = 1
	harness.check_equals(personality.calmness, 70, "personality copy is independent")


static func _test_places(harness: TestHarness) -> void:
	var all_day := NpcPlace.new("p", "Piazza", NpcPlace.Kind.SOCIAL, Vector2.ZERO)
	harness.check(all_day.is_open(0), "always-open place is open at midnight")
	harness.check(all_day.is_open(1439), "always-open place is open at 23:59")
	harness.check(not all_day.is_food_available(720), "a social place does not serve food")

	var inn := NpcPlace.new(
		"inn", "Locanda", NpcPlace.Kind.FOOD, Vector2(1, 2), 11 * 60, 23 * 60, true
	)
	harness.check(not inn.is_open(10 * 60), "the inn is closed before 11:00")
	harness.check(inn.is_open(11 * 60), "the inn opens at 11:00")
	harness.check(inn.is_open(22 * 60 + 59), "the inn is open just before 23:00")
	harness.check(not inn.is_open(23 * 60), "the inn closes at 23:00")
	harness.check(inn.is_food_available(12 * 60), "food is available while the inn is open")
	harness.check(not inn.is_food_available(23 * 60 + 1), "food is unavailable after closing")

	var night := NpcPlace.new("night", "Turno", NpcPlace.Kind.WORK, Vector2.ZERO, 22 * 60, 2 * 60)
	harness.check(night.is_open(23 * 60), "opening hours can wrap midnight (late)")
	harness.check(night.is_open(60), "opening hours can wrap midnight (early)")
	harness.check(not night.is_open(12 * 60), "wrapped hours are closed during the day")

	var registry := NpcPlaceRegistry.new()
	registry.add("home", "Casa", NpcPlace.Kind.HOME, Vector2(-10, 0), 0, 0, true)
	registry.add("food", "Mercato", NpcPlace.Kind.FOOD, Vector2(0, 0), 8 * 60, 18 * 60, true)
	registry.add("social", "Piazza", NpcPlace.Kind.SOCIAL, Vector2(2, 2))
	harness.check_equals(registry.get_count(), 3, "three places are registered")
	harness.check(registry.get_place("home") != null, "places are looked up by id")
	harness.check(registry.get_place("missing") == null, "unknown places return null")
	harness.check_equals(registry.home_places().size(), 1, "homes are queryable")
	harness.check(
		registry.find_food_place(9 * 60) != null, "food is found while the market is open"
	)
	harness.check(registry.find_food_place(20 * 60) != null, "the home pantry is a fallback")
	harness.check(registry.find_social_place(9 * 60) != null, "social places are found")
	harness.check(registry.validate().is_empty(), "the registry validates")


static func _test_record(harness: TestHarness) -> void:
	var record := NpcRecord.new()
	record.id = "npc_test"
	record.display_name = "Prova Vettori"
	record.age = 41
	record.profession_label = "Mercante"
	record.work_start_minute = 8 * 60
	record.work_end_minute = 16 * 60
	record.position = Vector2(3.0, -4.0)
	record.destination = Vector2(10.0, 2.0)
	record.destination_place_name = "Piazza"
	record.path = PackedVector2Array([Vector2(3, -4), Vector2(10, 2)])
	record.needs = NpcNeeds.new(55.0, 72.0, 48.0)
	record.personality = NpcPersonality.new(80, 30, 60, 70)
	record.relationships["npc_other"] = {"kind": "amico", "affinity": 30, "familiarity": 40}
	record.memories.append({"kind": "test", "text": "Una memoria.", "tick": 2})
	record.set_goal(NpcRecord.Goal.WORK, "test")
	record.set_activity(NpcRecord.Activity.WORKING, 12)
	record.has_destination = true
	harness.check(record.is_within_work_hours(9 * 60), "work hours are inclusive at the start")
	harness.check(
		not record.is_within_work_hours(16 * 60), "work hours are exclusive at the end"
	)
	harness.check(record.goal_label().contains("16:00"), "goal label formats the shift end")
	harness.check(record.activity_label().contains("mercante"), "activity label uses the job")
	harness.check(record.summary_text().contains("Prova Vettori"), "summary names the NPC")
	harness.check(record.destination_place_name == "Piazza", "destination name is stored")
	harness.check_equals(record.get_relationship_count(), 1, "seeded relationships are countable")
	harness.check_equals(record.get_memory_count(), 1, "seeded memories are countable")

	var snapshot := record.to_dict()
	var restored := NpcRecord.new()
	restored.from_dict(snapshot)
	harness.check_equals(restored.id, record.id, "id survives a round-trip")
	harness.check_equals(restored.display_name, record.display_name, "name survives a round-trip")
	harness.check_equals(restored.goal, record.goal, "goal survives a round-trip")
	harness.check_equals(restored.activity, record.activity, "activity survives a round-trip")
	harness.check_almost(restored.needs.hunger, record.needs.hunger, 0.0001, "needs survive")
	harness.check_equals(restored.path, record.path, "path survives a round-trip")
	harness.check_equals(
		restored.get_relationship_count(), 1, "relationships survive a round-trip"
	)
	restored.relationships.clear()
	harness.check_equals(
		record.get_relationship_count(), 1, "round-trip relationships are independent"
	)
