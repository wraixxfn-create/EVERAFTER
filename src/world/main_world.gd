extends Node3D
## MainWorld — the scene the project boots into, and the composition root of the
## 3D side of the game.
##
## It does three things and nothing else:
## 1. turns the deterministic world data (`VillageLayout`) into terrain, meshes
##    and colliders, once, at startup;
## 2. puts the player on a road, on the ground, facing the village;
## 3. publishes where the player is, so the HUD can name the area.
##
## Everything visual that changes over time lives in `SkyRig`; everything about
## the village shape lives in `src/world/environment/`. The dependency arrow is
## always `simulation -> world`, never the other way around: nothing in
## `simulation/` knows this scene exists, which is what keeps it testable
## headless.

const TAG := "World"

## Gap between the terrain surface and the centre of the player capsule:
## capsule height 1.8, so its feet end up on the ground instead of in it.
const SPAWN_CLEARANCE := 1.0
## The player arrives from the south-west road, a short walk from the plaza.
const SPAWN_ROAD_INDEX := 2
const SPAWN_DISTANCE := 30.0

var _terrain: TerrainGenerator = null
var _layout: VillageLayout = null
var _materials: VillageMaterials = null
var _areas: AreaRegistry = null
var _npc_system: NpcSimulationSystem = null
var _current_area := ""

@onready var _sky_rig: Node = $Sky
@onready var _terrain_mesh: MeshInstance3D = $Terrain/Mesh
@onready var _terrain_collision: CollisionShape3D = $Terrain/Collision
@onready var _village_root: Node3D = $Village
@onready var _npc_presenter: NpcPresenter = $NPCs
@onready var _player: PlayerExplorer = $Player


func _ready() -> void:
	var config := Game.config
	_materials = VillageMaterials.new()
	_layout = VillageLayout.new(
		config.terrain_seed, float(config.terrain_size_cells - 1) * 0.5
	)
	_terrain = TerrainGenerator.new(
		config.terrain_size_cells, config.terrain_height_scale, config.terrain_seed, _layout
	)
	_areas = _layout.build_area_registry()
	_build_terrain()
	_build_village()
	_configure_player(config)
	_build_inhabitants(config)
	GameLog.info(TAG, _build_summary())
	EventBus.world_ready.emit("MainWorld")


func _process(_delta: float) -> void:
	_publish_area()


# --- read-only access, used by the integration tests --------------------------


func get_terrain() -> TerrainGenerator:
	return _terrain


func get_layout() -> VillageLayout:
	return _layout


func get_area_registry() -> AreaRegistry:
	return _areas


func get_player() -> PlayerExplorer:
	return _player


func get_npc_system() -> NpcSimulationSystem:
	return _npc_system


func get_npc_presenter() -> NpcPresenter:
	return _npc_presenter


# --- construction ------------------------------------------------------------


func _build_terrain() -> void:
	_terrain_mesh.mesh = _terrain.build_mesh()
	_terrain_mesh.material_override = _terrain.build_material()
	_terrain_collision.shape = _terrain.build_collision_shape()


func _build_village() -> void:
	var builder := VillageBuilder.new(_layout, _terrain, _materials)
	_village_root.add_child(builder.build_village())
	# The rig drives the window and lantern glow, so it needs the shared palette.
	_sky_rig.set("village_materials", _materials)
	GameLog.info(TAG, "village — %s" % builder.summary())


func _build_inhabitants(config: GameConfig) -> void:
	var records := NpcRoster.build(config.npc_population_size)
	var places := VillageNpcPlaces.build(_layout, records)
	var obstacles := VillageNpcPlaces.build_obstacles(_layout)
	var route_graph := NpcRouteGraph.new(places, _layout.roads, obstacles)
	_npc_system = NpcSimulationSystem.new(records, places, route_graph)
	_npc_system.initialize(Game.get_tick())
	if not Game.set_npc_system(_npc_system):
		push_error("MainWorld: the NPC system could not be registered with Game.")
	for problem in _npc_system.validate():
		GameLog.warning(TAG, "inhabitants — %s" % problem)
	_npc_presenter.configure(
		_npc_system, _terrain, _player, config.npc_view_distance
	)
	GameLog.info(
		TAG,
		"inhabitants — %s; %s" % [_npc_system.summary(), _npc_system.validate()]
	)


func _configure_player(config: GameConfig) -> void:
	_player.walk_speed = config.player_walk_speed
	_player.sprint_speed = config.player_sprint_speed
	_player.jump_velocity = config.player_jump_velocity
	_player.mouse_sensitivity = config.mouse_sensitivity
	_player.world_half_extent = _terrain.get_half_extent()
	var spawn := _layout.point_on_road(SPAWN_ROAD_INDEX, SPAWN_DISTANCE)
	_player.global_position = Vector3(
		spawn.x, _terrain.height_at(spawn.x, spawn.y) + SPAWN_CLEARANCE, spawn.y
	)
	_player.look_toward(Vector3.ZERO)


# --- area tracking -----------------------------------------------------------


## Polls the registry and emits only on change: cheap enough to run every frame,
## quiet enough that the event bus stays a low frequency channel.
func _publish_area() -> void:
	if _areas == null or _player == null:
		return
	var flat := Vector2(_player.global_position.x, _player.global_position.z)
	var area := _areas.area_at(flat)
	if area != _current_area:
		_current_area = area
		EventBus.area_changed.emit(area)


func _build_summary() -> String:
	return (
		"MainWorld ready — terrain %dx%d cells (%.0f x %.0f u, %d tris), "
		+ "%d named areas, %d inhabitants, spawn %s"
		% [
			_terrain.size_cells,
			_terrain.size_cells,
			_terrain.get_extent(),
			_terrain.get_extent(),
			_terrain.get_triangle_count(),
			_areas.get_area_count(),
			_npc_system.get_record_count() if _npc_system != null else 0,
			_player.global_position,
		]
	)
