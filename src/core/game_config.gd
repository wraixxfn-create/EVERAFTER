class_name GameConfig
extends Resource
## Data-only tuning values for the whole project.
##
## A single, inspectable resource keeps magic numbers out of the code and lets
## a designer change the pace of the simulation or the size of the world from
## the editor (or from a text diff) without touching scripts.
##
## The instance used at runtime is loaded from [constant DEFAULT_CONFIG_PATH];
## if that file is missing or corrupt, [method load_or_default] falls back to
## the code defaults below so that the game always boots.
##
## NOTE: `persistence` is not implemented yet. [member save_format_version] is
## already reserved here so that future save files can be versioned from day
## one instead of being retrofitted later.

const DEFAULT_CONFIG_PATH := "res://config/game_config.tres"
const DEFAULT_TIME_SCALE_PRESETS := [1.0, 3.0, 10.0]
const DEFAULT_LOGIC_TICK_SECONDS := 0.05

@export_group("Project")
@export var project_title: String = "EVERAFTER"
@export var build_label: String = "0.5.0-social"

@export_group("Simulated time")
## Real seconds per logical tick at speed x1. With the default value the
## simulation runs 20 ticks per real second, so one simulated day
## (1440 ticks) lasts 72 real seconds at x1.
@export_range(0.005, 1.0, 0.005) var logic_tick_seconds: float = DEFAULT_LOGIC_TICK_SECONDS
## Speed multipliers selectable at runtime. First entry is the default speed.
@export var time_scale_presets: PackedFloat32Array = PackedFloat32Array([1.0, 3.0, 10.0])
@export var default_time_scale_index: int = 0
## Minute of day 1 the world starts on. 420 = 07:00, so the player begins at
## sunrise instead of in the dark.
@export_range(0, 1439) var start_minute_of_day: int = 420
## Safety valve: upper bound of ticks executed in a single frame, so that a
## long frame (alt-tab, breakpoint, loading spike) cannot freeze the game in a
## catch-up loop. Extra backlog is dropped instead of simulated.
@export_range(1, 120) var max_steps_per_frame: int = 12

@export_group("Persistence")
## Version written into future save files. Bump it whenever the serialised
## shape of the world changes.
@export var save_format_version: int = 1

@export_group("World")
## Number of grid points per side of the terrain height field. The terrain is
## (terrain_size_cells - 1) world units across. 160 -> 159x159 units, about
## 25k vertices / 50k triangles for the whole ground: comfortable on a
## GTX 1060 class GPU, and big enough that the village has fields, a road out
## of town and a tree line instead of ending at the last house.
@export_range(16, 512) var terrain_size_cells: int = 160
@export_range(0.0, 40.0) var terrain_height_scale: float = 5.0
## Every procedural element of the world derives from this seed, so the same
## seed always rebuilds the identical village.
@export var terrain_seed: int = 20261016

@export_group("Population")
## Inhabitants created at world start. The roster is fixed and deterministic;
## this value chooses how many of its entries are used. The requested phase
## asks for a small starting group, so the default sits inside 8..12.
@export_range(0, 16) var npc_population_size: int = 10
## Distance at which an inhabitant gets a 3D view. This only affects
## representation: simulation updates every NPC regardless of this value.
@export_range(10.0, 200.0) var npc_view_distance: float = 70.0

@export_group("Economy")
@export_range(0, 500) var starting_village_food: int = 24
@export_range(0, 500) var starting_village_wood: int = 12
@export_range(0, 500) var starting_village_stone: int = 10
@export_range(0, 1000) var starting_village_coin: int = 60

@export_group("Social")
## How many memories a single inhabitant keeps. Older or less important ones
## leave the book following the rule documented in `NpcMemory.retention_score()`.
@export_range(4, 200) var social_memory_capacity: int = 24
## Memories below this importance (0..100) are not stored at all: a hundred
## greetings must not fill a life.
@export_range(0, 100) var social_memory_importance_floor: int = 12
## Objective events kept in the social log, the raw material of the chronicle.
@export_range(10, 2000) var social_event_log_limit: int = 160
## World units: how close two inhabitants must be to interact.
@export_range(0.5, 20.0) var social_interaction_radius: float = 3.2
## Minimum simulated minutes between two interactions of the same pair.
@export_range(0, 1440) var social_cooldown_ticks: int = 45
## Positive points of trust/affinity/familiarity a pair can gain in one day.
## This is the brake that keeps repeated interactions from running away.
@export_range(1, 100) var social_daily_gain_cap: int = 14

@export_group("Player")
@export_range(0.5, 20.0) var player_walk_speed: float = 5.0
@export_range(0.5, 40.0) var player_sprint_speed: float = 9.0
@export_range(0.0, 20.0) var player_jump_velocity: float = 6.0
@export_range(0.0002, 0.02) var mouse_sensitivity: float = 0.0022


## Loads the project configuration, or a default instance when the resource is
## unavailable. Never returns null.
static func load_or_default(path: String = DEFAULT_CONFIG_PATH) -> GameConfig:
	if ResourceLoader.exists(path):
		var loaded := ResourceLoader.load(path) as GameConfig
		if loaded != null:
			return loaded
		push_warning("GameConfig: cannot read '%s' as a GameConfig, using code defaults." % path)
	else:
		push_warning("GameConfig: '%s' not found, using code defaults." % path)
	return GameConfig.new()


## Speed presets guaranteed to be usable, even if the resource was edited badly.
func validated_time_scale_presets() -> PackedFloat32Array:
	if time_scale_presets.is_empty():
		return PackedFloat32Array(DEFAULT_TIME_SCALE_PRESETS)
	return time_scale_presets


## Clamps a preset index into the valid range.
func clamped_time_scale_index(index: int) -> int:
	return clampi(index, 0, validated_time_scale_presets().size() - 1)


## Speed multiplier used when the game starts.
func initial_time_scale() -> float:
	return validated_time_scale_presets()[clamped_time_scale_index(default_time_scale_index)]


## Returns a list of human readable problems. Empty means "consistent".
## Called once at boot by the `Game` autoload; problems are logged, not fatal.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	var presets := validated_time_scale_presets()
	if project_title.is_empty():
		problems.append("project_title is empty")
	if logic_tick_seconds <= 0.0:
		problems.append("logic_tick_seconds must be > 0 (got %s)" % logic_tick_seconds)
	if time_scale_presets.is_empty():
		problems.append("time_scale_presets is empty, falling back to code defaults")
	for preset in time_scale_presets:
		if preset <= 0.0:
			problems.append("time_scale_presets must contain only values > 0 (got %s)" % preset)
			break
	if default_time_scale_index < 0 or default_time_scale_index >= presets.size():
		problems.append("default_time_scale_index out of range (got %d)" % default_time_scale_index)
	if terrain_size_cells < 4:
		problems.append("terrain_size_cells must be >= 4 (got %d)" % terrain_size_cells)
	if terrain_height_scale < 0.0:
		problems.append("terrain_height_scale must be >= 0 (got %s)" % terrain_height_scale)
	if player_walk_speed <= 0.0:
		problems.append("player_walk_speed must be > 0 (got %s)" % player_walk_speed)
	if npc_population_size < 0:
		problems.append("npc_population_size must be >= 0 (got %d)" % npc_population_size)
	if npc_view_distance <= 0.0:
		problems.append("npc_view_distance must be > 0 (got %s)" % npc_view_distance)
	if starting_village_food < 0:
		problems.append("starting_village_food must be >= 0 (got %d)" % starting_village_food)
	if starting_village_wood < 0:
		problems.append("starting_village_wood must be >= 0 (got %d)" % starting_village_wood)
	if starting_village_stone < 0:
		problems.append("starting_village_stone must be >= 0 (got %d)" % starting_village_stone)
	if starting_village_coin < 0:
		problems.append("starting_village_coin must be >= 0 (got %d)" % starting_village_coin)
	if social_memory_capacity < 1:
		problems.append("social_memory_capacity must be >= 1 (got %d)" % social_memory_capacity)
	if social_memory_importance_floor < 0 or social_memory_importance_floor > 100:
		problems.append(
			"social_memory_importance_floor must be inside 0..100 (got %d)"
			% social_memory_importance_floor
		)
	if social_event_log_limit < 1:
		problems.append("social_event_log_limit must be >= 1 (got %d)" % social_event_log_limit)
	if social_interaction_radius <= 0.0:
		problems.append(
			"social_interaction_radius must be > 0 (got %s)" % social_interaction_radius
		)
	if social_cooldown_ticks < 0:
		problems.append("social_cooldown_ticks must be >= 0 (got %d)" % social_cooldown_ticks)
	if social_daily_gain_cap < 1:
		problems.append("social_daily_gain_cap must be >= 1 (got %d)" % social_daily_gain_cap)
	if start_minute_of_day < 0 or start_minute_of_day >= SimulationClock.MINUTES_PER_DAY:
		problems.append("start_minute_of_day out of range (got %d)" % start_minute_of_day)
	if save_format_version < 1:
		problems.append("save_format_version must be >= 1 (got %d)" % save_format_version)
	return problems
