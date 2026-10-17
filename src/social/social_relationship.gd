class_name SocialRelationship
extends RefCounted
## One relationship between two inhabitants, identified by their id pair.
##
## ## Identity
## A relationship belongs to an *unordered* pair: "Elio knows Mira" and "Mira
## knows Elio" are one fact, not two. The pair is therefore stored in canonical
## form — [member a_id] is always the lexicographically smaller id, [member b_id]
## the larger one — and [method canonical_key] is the only way to build its key.
## Two inhabitants can never own two relationships between them: the
## `RelationshipGraph` refuses the duplicate instead of shadowing one entry.
##
## ## Which value belongs to whom
## Every attribute is an integer in `VALUE_MIN`..`VALUE_MAX` (0..100):
## * **shared** by the pair, one number seen identically from both sides:
##   [member familiarity] (how well they know each other) and [member tension]
##   (how strained the relationship is);
## * **directional**, one number per character and they can differ: trust and
##   affinity. `trust_a` is how much A trusts B, `trust_b` how much B trusts A;
##   `affinity_a` is how much A likes B, `affinity_b` the other way around.
##   Receiving help raises *your* trust in the helper, not the helper's in you.
##
## ## Why repeated interactions cannot run away
## [method gain_familiarity], [method gain_trust] and [method gain_affinity]
## apply two brakes before changing anything:
## 1. **diminishing returns** ([method scaled_gain]): a step is scaled by the
##    room left to the ceiling, so a value near 100 barely moves;
## 2. **a daily cap** ([member daily_gain_cap]): only the first
##    `daily_gain_cap` points of positive gain per simulated day are granted,
##    whatever the number of interactions.
## Both return the change *actually applied*, so the caller can log the truth
## instead of the intention. Negative changes are not capped: an argument can
## always damage a relationship.

const VALUE_MIN := 0
const VALUE_MAX := 100
const KEY_SEPARATOR := "|"
const DEFAULT_DAILY_GAIN_CAP := 14

## Canonical pair, `a_id < b_id` in lexicographic order.
var a_id: String = ""
var b_id: String = ""

## Shared: how well the two know each other. 0 = strangers, 100 = lifelong.
var familiarity: int = 0
## Shared: how strained the pair is. 0 = easy, 100 = open hostility.
var tension: int = 0
## Directional trust and affinity, one value per side of the pair.
var trust_a: int = 0
var trust_b: int = 0
var affinity_a: int = 0
var affinity_b: int = 0

## Positive points already granted today, and the day they belong to.
var gain_day_index: int = -1
var positive_gain_today: int = 0
## Tunable ceiling for [member positive_gain_today].
var daily_gain_cap: int = DEFAULT_DAILY_GAIN_CAP

var interaction_count: int = 0
var last_interaction_tick: int = -1
## Traceability for the UI: the last documented change and the event behind it.
var last_change_tick: int = -1
var last_change_event_id: String = ""
var last_change_reason: String = ""
## Where the relationship came from ("seme del roster", "primo incontro", ...).
var origin: String = ""


func _init(first_id: String = "", second_id: String = "", initial_origin: String = "") -> void:
	# Canonical order: the same two ids always produce the same relationship.
	if first_id <= second_id:
		a_id = first_id
		b_id = second_id
	else:
		a_id = second_id
		b_id = first_id
	origin = initial_origin


## The single key format used everywhere: sorted ids joined by a separator.
static func canonical_key(first_id: String, second_id: String) -> String:
	var first := first_id if first_id <= second_id else second_id
	var second := second_id if first_id <= second_id else first_id
	return "%s%s%s" % [first, KEY_SEPARATOR, second]


func key() -> String:
	return "%s%s%s" % [a_id, KEY_SEPARATOR, b_id]


func has_member(npc_id: String) -> bool:
	return npc_id == a_id or npc_id == b_id


## The other half of the pair. Returns an empty string for an id that is not a
## member, so a caller can detect the mistake instead of getting a wrong name.
func other_id(npc_id: String) -> String:
	if npc_id == a_id:
		return b_id
	if npc_id == b_id:
		return a_id
	return ""


func trust_of(npc_id: String) -> int:
	if npc_id == a_id:
		return trust_a
	if npc_id == b_id:
		return trust_b
	return VALUE_MIN


func affinity_of(npc_id: String) -> int:
	if npc_id == a_id:
		return affinity_a
	if npc_id == b_id:
		return affinity_b
	return VALUE_MIN


func _set_trust(npc_id: String, value: int) -> bool:
	var clamped := clampi(value, VALUE_MIN, VALUE_MAX)
	if npc_id == a_id:
		trust_a = clamped
		return true
	if npc_id == b_id:
		trust_b = clamped
		return true
	return false


func _set_affinity(npc_id: String, value: int) -> bool:
	var clamped := clampi(value, VALUE_MIN, VALUE_MAX)
	if npc_id == a_id:
		affinity_a = clamped
		return true
	if npc_id == b_id:
		affinity_b = clamped
		return true
	return false


## The weaker side of the pair, because a bond is only as strong as the least
## convinced of the two. Used to label the relationship and to rank it.
func _min_trust() -> int:
	return mini(trust_a, trust_b)


func _min_affinity() -> int:
	return mini(affinity_a, affinity_b)


## How strong this relationship is overall, as one comparable number. Tension
## weighs double because a strained bond is worse than a shallow one.
func strength() -> int:
	return familiarity + _min_trust() + _min_affinity() - tension * 2


## Diminishing returns: a step of [param amount] applied at [param current] is
## scaled by the room left to the ceiling. Pure arithmetic, no state.
static func scaled_gain(current: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var room_factor := 1.0 - clampf(float(current) / float(VALUE_MAX), 0.0, 1.0)
	return clampi(int(round(float(amount) * room_factor)), 0, amount)


## Points of positive gain still available today. Rolls the counter over when
## the day changes, which is what keeps a day of constant contact bounded.
func positive_room(day_index: int) -> int:
	if day_index != gain_day_index:
		return maxi(daily_gain_cap, 0)
	return maxi(daily_gain_cap - positive_gain_today, 0)


func _consume_room(day_index: int, granted: int) -> void:
	if day_index != gain_day_index:
		gain_day_index = day_index
		positive_gain_today = 0
	positive_gain_today += granted


## Grants familiarity, honouring the range, diminishing returns and the daily
## cap. Returns the points actually added (0 when nothing could be granted).
func gain_familiarity(amount: int, day_index: int) -> int:
	if amount <= 0:
		return 0
	var granted := mini(amount, positive_room(day_index))
	if granted <= 0:
		return 0
	var before := familiarity
	familiarity = clampi(familiarity + scaled_gain(familiarity, granted), VALUE_MIN, VALUE_MAX)
	var applied := familiarity - before
	_consume_room(day_index, applied)
	return applied


## Grants [param npc_id]'s trust in the other half of the pair.
func gain_trust(npc_id: String, amount: int, day_index: int) -> int:
	if amount <= 0:
		return 0
	var granted := mini(amount, positive_room(day_index))
	if granted <= 0:
		return 0
	var before := trust_of(npc_id)
	_set_trust(npc_id, before + scaled_gain(before, granted))
	var applied := trust_of(npc_id) - before
	_consume_room(day_index, applied)
	return applied


## Grants [param npc_id]'s affinity for the other half of the pair.
func gain_affinity(npc_id: String, amount: int, day_index: int) -> int:
	if amount <= 0:
		return 0
	var granted := mini(amount, positive_room(day_index))
	if granted <= 0:
		return 0
	var before := affinity_of(npc_id)
	_set_affinity(npc_id, before + scaled_gain(before, granted))
	var applied := affinity_of(npc_id) - before
	_consume_room(day_index, applied)
	return applied


## Damages trust: never capped, because a bad day must always be able to hurt.
func lose_trust(npc_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var before := trust_of(npc_id)
	_set_trust(npc_id, before - amount)
	return before - trust_of(npc_id)


func lose_affinity(npc_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var before := affinity_of(npc_id)
	_set_affinity(npc_id, before - amount)
	return before - affinity_of(npc_id)


## Moves the shared tension. Returns the change actually applied.
func shift_tension(amount: int) -> int:
	if amount == 0:
		return 0
	var before := tension
	tension = clampi(tension + amount, VALUE_MIN, VALUE_MAX)
	return tension - before


func clamp_all() -> void:
	familiarity = clampi(familiarity, VALUE_MIN, VALUE_MAX)
	tension = clampi(tension, VALUE_MIN, VALUE_MAX)
	trust_a = clampi(trust_a, VALUE_MIN, VALUE_MAX)
	trust_b = clampi(trust_b, VALUE_MIN, VALUE_MAX)
	affinity_a = clampi(affinity_a, VALUE_MIN, VALUE_MAX)
	affinity_b = clampi(affinity_b, VALUE_MIN, VALUE_MAX)
	positive_gain_today = maxi(positive_gain_today, 0)
	interaction_count = maxi(interaction_count, 0)


## Short label derived from the numbers, never stored: a stored label would be
## a second source of truth able to contradict the values it describes.
func kind_label() -> String:
	if tension >= 55:
		return "in conflitto"
	if tension >= 30:
		return "rapporti tesi"
	if _min_trust() >= 70 and _min_affinity() >= 55:
		return "legame stretto"
	if _min_trust() >= 45 and _min_affinity() >= 30:
		return "buoni rapporti"
	if familiarity >= 20:
		return "conoscenza"
	return "volti noti"


func is_valid() -> bool:
	return (
		not a_id.is_empty()
		and not b_id.is_empty()
		and a_id != b_id
		and a_id < b_id
		and familiarity >= VALUE_MIN and familiarity <= VALUE_MAX
		and tension >= VALUE_MIN and tension <= VALUE_MAX
		and trust_a >= VALUE_MIN and trust_a <= VALUE_MAX
		and trust_b >= VALUE_MIN and trust_b <= VALUE_MAX
		and affinity_a >= VALUE_MIN and affinity_a <= VALUE_MAX
		and affinity_b >= VALUE_MIN and affinity_b <= VALUE_MAX
	)


func to_dict() -> Dictionary:
	return {
		"a_id": a_id,
		"b_id": b_id,
		"familiarity": familiarity,
		"tension": tension,
		"trust_a": trust_a,
		"trust_b": trust_b,
		"affinity_a": affinity_a,
		"affinity_b": affinity_b,
		"gain_day_index": gain_day_index,
		"positive_gain_today": positive_gain_today,
		"daily_gain_cap": daily_gain_cap,
		"interaction_count": interaction_count,
		"last_interaction_tick": last_interaction_tick,
		"last_change_tick": last_change_tick,
		"last_change_event_id": last_change_event_id,
		"last_change_reason": last_change_reason,
		"origin": origin,
	}


func from_dict(data: Dictionary) -> void:
	a_id = String(data.get("a_id", a_id))
	b_id = String(data.get("b_id", b_id))
	familiarity = int(data.get("familiarity", familiarity))
	tension = int(data.get("tension", tension))
	trust_a = int(data.get("trust_a", trust_a))
	trust_b = int(data.get("trust_b", trust_b))
	affinity_a = int(data.get("affinity_a", affinity_a))
	affinity_b = int(data.get("affinity_b", affinity_b))
	gain_day_index = int(data.get("gain_day_index", gain_day_index))
	positive_gain_today = int(data.get("positive_gain_today", positive_gain_today))
	daily_gain_cap = int(data.get("daily_gain_cap", daily_gain_cap))
	interaction_count = int(data.get("interaction_count", interaction_count))
	last_interaction_tick = int(data.get("last_interaction_tick", last_interaction_tick))
	last_change_tick = int(data.get("last_change_tick", last_change_tick))
	last_change_event_id = String(data.get("last_change_event_id", last_change_event_id))
	last_change_reason = String(data.get("last_change_reason", last_change_reason))
	origin = String(data.get("origin", origin))
	clamp_all()


func _to_string() -> String:
	return "%s — %s (%s)" % [key(), kind_label(), familiarity]
