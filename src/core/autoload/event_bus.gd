extends Node
## EventBus — autoload singleton (registered as `EventBus` in project.godot).
##
## One narrow, well known place where modules can talk without knowing each
## other: simulation -> UI, world -> UI, and later history/chronicles.
##
## Rules for this file:
## * Only declare signals that are actually emitted and consumed today. Dead
##   signals become lies in the documentation, so new ones are added together
##   with their first producer and consumer (see `docs/ROADMAP.md`).
## * Signals carry plain values (int, float, String, Dictionary) so that no
##   subscriber needs to import a scene or a node type.
## * Low frequency only: per-tick traffic is *not* broadcast here, systems get
##   it through `SimulationSystem.on_tick()` instead.

## Emitted by the `Game` autoload when the simulated date rolls over.
## [param display_day] starts at 1, [param minute_of_day] is 0 at midnight.
signal day_advanced(display_day: int, minute_of_day: int)

## Emitted by the `Game` autoload when the player changes the simulation speed.
signal time_scale_changed(time_scale: float)

## Emitted by the `Game` autoload when the simulation is paused or resumed.
signal simulation_paused_changed(is_paused: bool)

## Emitted when a 3D world scene finished assembling itself.
signal world_ready(world_name: String)

## Emitted by the world when the player crosses into a differently named region
## (`AreaRegistry`). Low frequency by construction: it fires only on change, so
## the HUD can show "where am I" without polling the world every frame.
signal area_changed(area_name: String)

## Emitted by `PlayerExplorer` when the mouse is captured or released, so the
## HUD can show how to get the controls back.
signal mouse_capture_changed(is_captured: bool)

## Emitted by the `Game` autoload when the world has registered its inhabitant
## simulation. The UI listens once instead of polling a null system at boot.
signal npc_system_ready

## Emitted by the `Game` autoload when the world has registered its economy
## simulation.
signal economy_system_ready

## Emitted by the `Game` autoload when the world has registered the social
## simulation (relationships, interactions and memories).
signal social_system_ready

## Emitted by the NPC presenter (click in the world) and by the observation
## panel (list selection). Carries a plain NPC id; subscribers query the
## simulation for the data they need.
signal npc_selected(npc_id: String)
