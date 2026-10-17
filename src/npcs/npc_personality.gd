class_name NpcPersonality
extends RefCounted
## Four simple, readable personality axes used by the NPC rules.
##
## The values are integers in `0..100` so that they are easy to inspect in the
## UI, to tune in a data table and to serialise later:
## * [member diligence] — how strongly the character sticks to work hours;
## * [member sociability] — how likely free time is spent around other people;
## * [member curiosity] — reserved for exploration and future systems;
## * [member calmness] — how quickly wellbeing recovers.
##
## This class is pure data. It has no reference to the scene tree, to a node or
## to the rest of the NPC simulation, and `tests/unit/test_npc_data.gd` checks
## that the values always stay inside their declared range.

const MIN_VALUE := 0
const MAX_VALUE := 100

var diligence: int = 50
var sociability: int = 50
var curiosity: int = 50
var calmness: int = 50


func _init(
	initial_diligence: int = 50,
	initial_sociability: int = 50,
	initial_curiosity: int = 50,
	initial_calmness: int = 50
) -> void:
	diligence = clampi(initial_diligence, MIN_VALUE, MAX_VALUE)
	sociability = clampi(initial_sociability, MIN_VALUE, MAX_VALUE)
	curiosity = clampi(initial_curiosity, MIN_VALUE, MAX_VALUE)
	calmness = clampi(initial_calmness, MIN_VALUE, MAX_VALUE)


## Clamps every axis after a change made by a caller or by a save file.
func clamp_all() -> void:
	diligence = clampi(diligence, MIN_VALUE, MAX_VALUE)
	sociability = clampi(sociability, MIN_VALUE, MAX_VALUE)
	curiosity = clampi(curiosity, MIN_VALUE, MAX_VALUE)
	calmness = clampi(calmness, MIN_VALUE, MAX_VALUE)


func copy() -> NpcPersonality:
	return NpcPersonality.new(diligence, sociability, curiosity, calmness)


func to_dict() -> Dictionary:
	return {
		"diligence": diligence,
		"sociability": sociability,
		"curiosity": curiosity,
		"calmness": calmness,
	}


func from_dict(data: Dictionary) -> void:
	diligence = int(data.get("diligence", diligence))
	sociability = int(data.get("sociability", sociability))
	curiosity = int(data.get("curiosity", curiosity))
	calmness = int(data.get("calmness", calmness))
	clamp_all()


func _to_string() -> String:
	return "diligenza %d, socievolezza %d, curiosità %d, calma %d" % [
		diligence, sociability, curiosity, calmness
	]
