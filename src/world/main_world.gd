extends Node3D
## MainWorld — the 3D scene the project boots into.
##
## Responsibilities:
## * turn the deterministic world data (terrain height field, village layout)
##   into nodes, once, at startup;
## * read the state published by the simulation each frame and express it
##   visually (right now: the sun and the sky follow the simulated hour).
##
## The dependency arrow is always `simulation -> world`, never the other way
## around: nothing in `simulation/` knows that this scene exists, which is what
## keeps the simulation testable headless.

const TAG := "World"

const VILLAGE_HOUSES := 8
const VILLAGE_TREES := 24
## Gap between the terrain surface and the centre of the player capsule.
const SPAWN_CLEARANCE := 1.0
const SPAWN_OFFSET := Vector3(0.0, 0.0, 9.0)

const SKY_TOP_NIGHT := Color(0.02, 0.03, 0.08)
const SKY_TOP_DAY := Color(0.22, 0.40, 0.70)
const SKY_HORIZON_NIGHT := Color(0.06, 0.07, 0.13)
const SKY_HORIZON_DAY := Color(0.68, 0.76, 0.86)
const GROUND_NIGHT := Color(0.03, 0.04, 0.06)
const GROUND_DAY := Color(0.22, 0.22, 0.20)
const SUN_COLOR_DAY := Color(1.00, 0.96, 0.88)
const SUN_COLOR_LOW := Color(1.00, 0.52, 0.26)
const SUN_ENERGY_DAY := 1.25
const SUN_ENERGY_NIGHT := 0.06
const AMBIENT_ENERGY_DAY := 1.0
const AMBIENT_ENERGY_NIGHT := 0.18

var _terrain: TerrainGenerator = null

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun
@onready var _terrain_mesh: MeshInstance3D = $Terrain/Mesh
@onready var _terrain_collision: CollisionShape3D = $Terrain/Collision
@onready var _props_root: Node3D = $Props
@onready var _player: PlayerExplorer = $Player


func _ready() -> void:
	var config := Game.config
	_terrain = TerrainGenerator.new(
		config.terrain_size_cells, config.terrain_height_scale, config.terrain_seed
	)
	_build_terrain()
	_build_props(config)
	_configure_player(config)
	GameLog.info(TAG, _build_summary())
	EventBus.world_ready.emit("MainWorld")


## Reads simulation state and applies it. Runs every frame, but the values only
## change once per tick, so at speed x1 the sun moves 20 times per second.
func _process(_delta: float) -> void:
	_apply_day_cycle()


# --- construction ------------------------------------------------------------


func _build_terrain() -> void:
	_terrain_mesh.mesh = _terrain.build_mesh()
	_terrain_mesh.material_override = _terrain.build_material()
	_terrain_collision.shape = _terrain.build_collision_shape()


func _build_props(config: GameConfig) -> void:
	var builder := PropBuilder.new(_terrain, config.terrain_seed)
	_props_root.add_child(builder.build_village(VILLAGE_HOUSES, VILLAGE_TREES))


func _configure_player(config: GameConfig) -> void:
	_player.walk_speed = config.player_walk_speed
	_player.sprint_speed = config.player_sprint_speed
	_player.jump_velocity = config.player_jump_velocity
	_player.mouse_sensitivity = config.mouse_sensitivity
	var spawn := SPAWN_OFFSET
	spawn.y = _terrain.height_at(spawn.x, spawn.z) + SPAWN_CLEARANCE
	_player.global_position = spawn


# --- presentation of simulation state ----------------------------------------


func _apply_day_cycle() -> void:
	var day_cycle := Game.get_day_cycle()
	if day_cycle == null or _sun == null:
		return
	_sun.transform = Transform3D(_sun_basis(day_cycle), Vector3.ZERO)
	var daylight := day_cycle.get_daylight_factor()
	_sun.light_energy = lerpf(SUN_ENERGY_NIGHT, SUN_ENERGY_DAY, daylight)
	_sun.light_color = SUN_COLOR_DAY.lerp(SUN_COLOR_LOW, _horizon_glow(daylight))
	if _world_environment == null or _world_environment.environment == null:
		return
	var environment := _world_environment.environment
	environment.ambient_light_energy = lerpf(AMBIENT_ENERGY_NIGHT, AMBIENT_ENERGY_DAY, daylight)
	if environment.sky == null:
		return
	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	if sky_material == null:
		return
	sky_material.sky_top_color = SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, daylight)
	sky_material.sky_horizon_color = SKY_HORIZON_NIGHT.lerp(SKY_HORIZON_DAY, daylight)
	sky_material.ground_horizon_color = SKY_HORIZON_NIGHT.lerp(SKY_HORIZON_DAY, daylight)
	sky_material.ground_bottom_color = GROUND_NIGHT.lerp(GROUND_DAY, daylight)
	sky_material.sun_angle_max = 8.0 + 24.0 * _horizon_glow(daylight)
	environment.fog_light_color = SKY_HORIZON_NIGHT.lerp(SKY_HORIZON_DAY, daylight)


func _sun_basis(day_cycle: DayCycleSystem) -> Basis:
	var basis := Basis()
	basis = basis.rotated(Vector3.UP, deg_to_rad(day_cycle.sun_azimuth_deg))
	# The light shines along -Z, so a positive elevation has to pitch it down.
	basis = basis.rotated(basis.x, deg_to_rad(-day_cycle.sun_elevation_deg))
	return basis.orthonormalized()


## 0.0 when the sun is high or far below the horizon, 1.0 around sunrise/sunset.
func _horizon_glow(daylight: float) -> float:
	return clampf(1.0 - absf(daylight - 0.3) / 0.3, 0.0, 1.0)


func _build_summary() -> String:
	return (
		"MainWorld ready — terrain %dx%d cells (%.0f x %.0f u, %d tris), %d houses, %d trees, spawn %s"
		% [
			_terrain.size_cells,
			_terrain.size_cells,
			_terrain.get_extent(),
			_terrain.get_extent(),
			_terrain.get_triangle_count(),
			VILLAGE_HOUSES,
			VILLAGE_TREES,
			_player.global_position,
		]
	)
