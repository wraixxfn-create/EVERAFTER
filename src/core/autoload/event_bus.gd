extends Node
## EventBus — autoload singleton (registered as `EventBus` in `project.godot`).
##
## One narrow, well known place where modules can talk without knowing each
## other: simulation -> UI, world -> UI, persistence -> UI, history -> UI.
##
## Rules for this file:
## * Only declare signals that are actually emitted and consumed today.
## * Signals carry plain values (int, float, String, Dictionary).
## * Low frequency only: per-tick traffic is *not* broadcast here.

## Emitted by the `Game` autoload when the simulated date rolls over.
signal day_advanced(display_day: int, minute_of_day: int)

## Emitted by the `Game` autoload when the player changes the simulation speed.
signal time_scale_changed(time_scale: float)

## Emitted by the `Game` autoload when the simulation is paused or resumed.
signal simulation_paused_changed(is_paused: bool)

## Emitted when the world finishes being built (and any load/catch-up ran).
signal world_ready(world_name: String)

## Emitted by the world when the player crosses into a differently named region.
signal area_changed(area_name: String)

## Emitted by `PlayerExplorer` when the mouse is captured or released.
signal mouse_capture_changed(is_captured: bool)

## Emitted by `Game` when a simulation system has been registered.
signal npc_system_ready
signal economy_system_ready
signal social_system_ready

## Emitted when an NPC is selected (world click or panel list).
signal npc_selected(npc_id: String)

## Emitted after a successful save, so the UI can refresh its metadata.
signal save_performed

## Emitted when the chronicle gains new entries (bulk-aware: emitted once per
## frame if new entries were appended during that frame, not once per entry).
signal chronicle_updated
