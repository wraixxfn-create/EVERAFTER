class_name RelationshipGraph
extends RefCounted
## The single owner of every relationship in the world.
##
## Relationships are stored once, keyed by the canonical id pair
## ([method SocialRelationship.canonical_key]), and indexed here — not copied
## into both records. Two inhabitants can therefore never hold two diverging
## copies of the same bond, which is the bug a symmetric per-record dictionary
## makes possible.
##
## Rules:
## * [method create] refuses an empty id, a self-relationship and a duplicate
##   pair, and returns `null` when it refuses: a caller cannot silently end up
##   with two relationships between the same two people;
## * [method get_relationship] accepts the ids in any order, because the pair is
##   unordered;
## * [method remove_orphans] drops every relationship that points at an id the
##   world no longer knows, which is what keeps a save file or a roster change
##   from leaving references dangling;
## * iteration is always over the insertion-ordered key list, never over the
##   dictionary directly, so the same world always produces the same sequence.
##
## This class is pure data: no node, no scene, no clock.

var _by_key: Dictionary = {}
## Insertion order. Kept explicitly so iteration never depends on hashing.
var _keys: Array[String] = []


## Creates a relationship, or returns `null` when it is invalid or already
## exists. The caller must handle `null`: nothing is created behind its back.
func create(first_id: String, second_id: String, origin: String = "") -> SocialRelationship:
	if first_id.is_empty() or second_id.is_empty():
		push_error("RelationshipGraph: both ids are required to create a relationship.")
		return null
	if first_id == second_id:
		push_error("RelationshipGraph: '%s' cannot have a relationship with itself." % first_id)
		return null
	var pair_key := SocialRelationship.canonical_key(first_id, second_id)
	if _by_key.has(pair_key):
		push_error("RelationshipGraph: relationship '%s' already exists." % pair_key)
		return null
	var relationship := SocialRelationship.new(first_id, second_id, origin)
	_by_key[pair_key] = relationship
	_keys.append(pair_key)
	return relationship


## Returns the existing relationship between the two ids, creating it when it
## does not exist yet. Never returns `null` for a valid, non-self pair.
func ensure(first_id: String, second_id: String, origin: String = "") -> SocialRelationship:
	var existing := get_relationship(first_id, second_id)
	if existing != null:
		return existing
	return create(first_id, second_id, origin)


func get_relationship(first_id: String, second_id: String) -> SocialRelationship:
	if first_id.is_empty() or second_id.is_empty() or first_id == second_id:
		return null
	return _by_key.get(SocialRelationship.canonical_key(first_id, second_id), null) \
		as SocialRelationship


func has_relationship(first_id: String, second_id: String) -> bool:
	return get_relationship(first_id, second_id) != null


func count() -> int:
	return _keys.size()


## Insertion-ordered keys. The list is a copy: a caller cannot corrupt the index.
func keys() -> Array[String]:
	return _keys.duplicate()


func all_relationships() -> Array[SocialRelationship]:
	var result: Array[SocialRelationship] = []
	for pair_key in _keys:
		result.append(_by_key[pair_key] as SocialRelationship)
	return result


## Relationships of one inhabitant, in graph order (stable between runs).
func relationships_of(npc_id: String) -> Array[SocialRelationship]:
	var result: Array[SocialRelationship] = []
	if npc_id.is_empty():
		return result
	for pair_key in _keys:
		var relationship := _by_key[pair_key] as SocialRelationship
		if relationship.has_member(npc_id):
			result.append(relationship)
	return result


## Ids of everybody this inhabitant has a relationship with.
func partner_ids_of(npc_id: String) -> Array[String]:
	var result: Array[String] = []
	for relationship in relationships_of(npc_id):
		var partner := relationship.other_id(npc_id)
		if not partner.is_empty():
			result.append(partner)
	return result


func remove(first_id: String, second_id: String) -> bool:
	if first_id.is_empty() or second_id.is_empty() or first_id == second_id:
		return false
	var pair_key := SocialRelationship.canonical_key(first_id, second_id)
	if not _by_key.has(pair_key):
		return false
	_by_key.erase(pair_key)
	_keys.erase(pair_key)
	return true


func clear() -> void:
	_by_key.clear()
	_keys.clear()


## Drops relationships whose members are not in [param known_ids] (a set of
## `id -> true`). Returns how many were removed. A relationship with a missing
## inhabitant cannot be interpreted, and keeping it would mean showing the
## player a bond with somebody who does not exist.
func remove_orphans(known_ids: Dictionary) -> int:
	var orphans: Array[String] = []
	for pair_key in _keys:
		var relationship := _by_key[pair_key] as SocialRelationship
		if not known_ids.has(relationship.a_id) or not known_ids.has(relationship.b_id):
			orphans.append(pair_key)
	for pair_key in orphans:
		_by_key.erase(pair_key)
		_keys.erase(pair_key)
	return orphans.size()


## Human readable problems. An empty array means the graph is consistent.
func validate(known_ids: Dictionary = {}) -> PackedStringArray:
	var problems: PackedStringArray = []
	var seen: Dictionary = {}
	for pair_key in _keys:
		if not _by_key.has(pair_key):
			problems.append("key '%s' is indexed but missing" % pair_key)
			continue
		var relationship := _by_key[pair_key] as SocialRelationship
		if seen.has(pair_key):
			problems.append("duplicate relationship '%s'" % pair_key)
		seen[pair_key] = true
		if relationship.key() != pair_key:
			problems.append("'%s' is stored under the wrong key" % pair_key)
		if not relationship.is_valid():
			problems.append("relationship '%s' has invalid values" % pair_key)
		if not known_ids.is_empty():
			if not known_ids.has(relationship.a_id):
				problems.append("'%s' refers to unknown inhabitant '%s'" % [pair_key, relationship.a_id])
			if not known_ids.has(relationship.b_id):
				problems.append("'%s' refers to unknown inhabitant '%s'" % [pair_key, relationship.b_id])
	for pair_key in _by_key.keys():
		if not _keys.has(pair_key):
			problems.append("relationship '%s' exists but is not indexed" % pair_key)
	return problems


func to_dict() -> Dictionary:
	var entries: Array = []
	for pair_key in _keys:
		entries.append((_by_key[pair_key] as SocialRelationship).to_dict())
	return {"keys": _keys.duplicate(), "relationships": entries}


func from_dict(data: Dictionary) -> void:
	clear()
	var entries: Array = data.get("relationships", [])
	for entry in entries:
		var relationship := SocialRelationship.new()
		relationship.from_dict(entry as Dictionary)
		if relationship.a_id.is_empty() or relationship.b_id.is_empty():
			continue
		var pair_key := relationship.key()
		if _by_key.has(pair_key):
			# A save file with a duplicated pair must not create two bonds: the
			# first entry wins and the duplicate is reported instead.
			push_warning("RelationshipGraph: ignoring duplicated pair '%s'." % pair_key)
			continue
		_by_key[pair_key] = relationship
		_keys.append(pair_key)


func _to_string() -> String:
	return "%d relazioni" % _keys.size()
