class_name TestNpcRoster
extends RefCounted
## Checks that the starting population is deterministic, unique and individual:
## no duplicated IDs, stable names between builds, varied data and relationship
## entries that never point at an inhabitant outside the requested group.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("NpcRoster")

	var records := NpcRoster.build(10)
	harness.check_equals(records.size(), 10, "ten inhabitants are created")
	var ids := {}
	var names := {}
	for record in records:
		harness.check(not record.id.is_empty(), "every inhabitant has an id")
		harness.check(not names.has(record.display_name), "names are unique")
		names[record.display_name] = true
		harness.check(not ids.has(record.id), "ids are unique")
		ids[record.id] = true
		harness.check(record.age >= 18, "every inhabitant is an adult")
		harness.check(record.personality.diligence >= 0, "personality is populated")
		harness.check(record.needs.energy > 0.0, "initial energy is populated")
		harness.check(record.get_memory_count() >= 2, "memories are seeded")
		harness.check(record.work_start_minute < record.work_end_minute, "work hours are sane")

	var second_build := NpcRoster.build(10)
	harness.check_equals(
		_name_list(records), _name_list(second_build), "names are stable between builds"
	)
	harness.check_equals(_id_list(records), _id_list(second_build), "ids are stable between builds")

	var smaller := NpcRoster.build(4)
	harness.check_equals(smaller.size(), 4, "the population size is configurable")
	harness.check_equals(
		_name_list(smaller), _name_list(records).slice(0, 4),
		"a smaller population is a stable prefix of the catalogue"
	)
	harness.check_equals(NpcRoster.build(0).size(), 0, "zero inhabitants is a valid request")
	var clamped := NpcRoster.build(999)
	harness.check_equals(
		clamped.size(), NpcRoster.MAX_POPULATION, "the roster never invents entries beyond the table"
	)

	# Relationships must never point outside the requested group.
	var existing := {}
	for record in smaller:
		existing[record.id] = true
	for record in smaller:
		for other_id in record.relationships.keys():
			harness.check(
				existing.has(other_id),
				"relationship points at an inhabitant inside the group (%s -> %s)"
				% [record.id, other_id]
			)
		harness.check(
			record.get_relationship_count() > 0, "every inhabitant starts with a relationship"
		)

	# Different inhabitants must not share the same initial state object.
	harness.check(records[0].needs != records[1].needs, "needs are per-inhabitant objects")
	harness.check(
		records[0].personality != records[1].personality,
		"personalities are per-inhabitant objects"
	)
	harness.check_not_equals(
		records[0].age, records[1].age, "ages differ between inhabitants"
	)
	harness.check_not_equals(
		records[0].profession_id, records[1].profession_id, "professions differ"
	)


static func _name_list(records: Array[NpcRecord]) -> PackedStringArray:
	var names: PackedStringArray = []
	for record in records:
		names.append(record.display_name)
	return names


static func _id_list(records: Array[NpcRecord]) -> PackedStringArray:
	var ids: PackedStringArray = []
	for record in records:
		ids.append(record.id)
	return ids
