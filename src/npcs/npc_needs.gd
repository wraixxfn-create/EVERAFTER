class_name NpcNeeds
extends RefCounted
## The three needs simulated in this phase: energy, hunger and wellbeing.
##
## Each need is a float in `0..100`:
## * [member energy] — 100 is fully rested, 0 is exhausted;
## * [member hunger] — 0 is full, 100 is starving (the axis points *towards*
##   hunger on purpose, so "hunger high" always means "must eat");
## * [member wellbeing] — 100 is content, 0 is miserable.
##
## The class only stores and clamps values. The rates that change them belong to
## `NpcSimulationSystem`, so a test can advance one need in isolation and the
## rules stay in one readable place.

const MIN_VALUE := 0.0
const MAX_VALUE := 100.0

var energy: float = 80.0
var hunger: float = 20.0
var wellbeing: float = 70.0


func _init(
	initial_energy: float = 80.0,
	initial_hunger: float = 20.0,
	initial_wellbeing: float = 70.0
) -> void:
	energy = clampf(initial_energy, MIN_VALUE, MAX_VALUE)
	hunger = clampf(initial_hunger, MIN_VALUE, MAX_VALUE)
	wellbeing = clampf(initial_wellbeing, MIN_VALUE, MAX_VALUE)


func clamp_all() -> void:
	energy = clampf(energy, MIN_VALUE, MAX_VALUE)
	hunger = clampf(hunger, MIN_VALUE, MAX_VALUE)
	wellbeing = clampf(wellbeing, MIN_VALUE, MAX_VALUE)


func copy() -> NpcNeeds:
	return NpcNeeds.new(energy, hunger, wellbeing)


## 0.0 when every need is in a good place, 1.0 when the character is spent.
## True when every need is a finite number inside the documented range. Used by
## `NpcSimulationSystem.validate()` before a world trusts its population.
func are_valid() -> bool:
	return (
		is_finite(energy) and is_finite(hunger) and is_finite(wellbeing)
		and energy >= MIN_VALUE and energy <= MAX_VALUE
		and hunger >= MIN_VALUE and hunger <= MAX_VALUE
		and wellbeing >= MIN_VALUE and wellbeing <= MAX_VALUE
	)


func get_pressure() -> float:
	var tired := 1.0 - energy / MAX_VALUE
	var hungry := hunger / MAX_VALUE
	var unhappy := 1.0 - wellbeing / MAX_VALUE
	return clampf((tired + hungry + unhappy) / 3.0, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"energy": energy,
		"hunger": hunger,
		"wellbeing": wellbeing,
	}


func from_dict(data: Dictionary) -> void:
	energy = float(data.get("energy", energy))
	hunger = float(data.get("hunger", hunger))
	wellbeing = float(data.get("wellbeing", wellbeing))
	clamp_all()


func _to_string() -> String:
	return "energia %.0f, fame %.0f, benessere %.0f" % [energy, hunger, wellbeing]
