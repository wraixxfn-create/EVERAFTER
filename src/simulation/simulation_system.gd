class_name SimulationSystem
extends RefCounted
## Base class for every system that advances the civilisation.
##
## A system is plain data plus rules: no nodes, no scenes, no rendering. That
## is what makes the simulation testable headless (`godot --headless`) and,
## later, able to "catch up" on time spent while the player was away.
##
## Contract for every subclass:
## * [method on_tick] must be deterministic: same tick number + same system
##   state must always produce the same new state. Do not read frame time,
##   input, `randf()` (use the shared seeded generator instead), the wall
##   clock or the scene tree in here.
## * A system never touches the scene tree. It publishes state; the world and
##   the UI read that state (see `DayCycleSystem` + `MainWorld`).
## * [method to_dict] / [method from_dict] must round-trip everything the
##   system owns, so that saves keep working when the system grows.
##
## GDScript has no abstract methods: the base implementations are no-ops and
## the names below are the convention every subclass follows.

const BASE_SYSTEM_NAME := "SimulationSystem"

## Systems can be disabled at runtime without being unregistered, which keeps
## the tick order of the remaining systems stable.
var enabled: bool = true


## Unique, stable name. Used by `SimulationLoop.get_system()` and by save files.
func get_system_name() -> String:
	return BASE_SYSTEM_NAME


## Called exactly once per logical tick, in registration order.
func on_tick(_tick: int, _clock: SimulationClock) -> void:
	pass


## Restores the initial state (used by tests and by "new world").
func reset() -> void:
	pass


## Serialisable snapshot for the future `persistence` module.
func to_dict() -> Dictionary:
	return {}


## Restores a snapshot produced by [method to_dict].
func from_dict(_data: Dictionary) -> void:
	pass
