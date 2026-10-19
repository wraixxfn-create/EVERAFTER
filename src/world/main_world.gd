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
## Once everything is built, [method _build_finished] lets `Game` know so that a
## save can be loaded and offline catch-up applied. Nothing in `simulation/`
## knows this scene exists, which is what keeps it testable headless.

const TAG := "World"

## Gap between the terrain surface and the centre of the player capsule.
const SPAWN_CLEARANCE := 1.0
const SPAWN_ROAD_INDEX := 2
# Structural correction 11: spawn was 30 u out, hiding the skyline at
# medium distance. Now 22 u: plaza, inn, hall and pond all in first frame.
const SPAWN_DISTANCE := 22.0

var _terrain: TerrainGenerator = null
var _layout: VillageLayout = null
var _materials: VillageMaterials = null
var _areas: AreaRegistry = null
var _npc_system: NpcSimulationSystem = null
var _economy_system: EconomySystem = null
var _social_system: SocialSystem = null
var _current_area := ""
var _boot_summary: Dictionary = {}

@onready var _sky_rig: Node = $Sky
@onready var _terrain_mesh: MeshInstance3D = $Terrain/Mesh
@onready var _terrain_collision: CollisionShape3D = $Terrain/Collision
@onready var _village_root: Node3D = $Village
@onready var _npc_presenter: NpcPresenter = $NPCs
@onready var _player: PlayerExplorer = $Player
@onready var _world_map: WorldMap = $WorldMap


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
	var population := Game.get_saved_population_size()
	_build_inhabitants(config, population)
	GameLog.info(TAG, _build_summary())
	_boot_summary = Game.world_build_finished()
	if _boot_summary.get("loaded", false):
		GameLog.info(TAG, "save loaded: %s" % _boot_summary.get("message", ""))
		if _boot_summary.has("catchup"):
			var c: Dictionary = _boot_summary["catchup"]
			GameLog.info(TAG, "catchup: %s" % c.get("message", ""))
	_npc_presenter.force_refresh()
	_world_map.player = _player
	_world_map.npc_system = _npc_system
	_world_map.world_extent = _terrain.get_half_extent()
	_add_save_panel()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_toggle_world_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _world_map.visible:
		_toggle_world_map()
		get_viewport().set_input_as_handled()


func _toggle_world_map() -> void:
	_world_map.visible = not _world_map.visible
	_player.set_mouse_captured(not _world_map.visible)


func _process(_delta: float) -> void:
	_publish_area()


# --- read-only access --------------------------------------------------------


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


func get_economy_system() -> EconomySystem:
	return _economy_system


func get_social_system() -> SocialSystem:
	return _social_system


func get_npc_presenter() -> NpcPresenter:
	return _npc_presenter


func get_boot_summary() -> Dictionary:
	return _boot_summary


# --- construction ------------------------------------------------------------


func _build_terrain() -> void:
	_terrain_mesh.mesh = _terrain.build_mesh()
	_terrain_mesh.material_override = _terrain.build_material()
	_terrain_collision.shape = _terrain.build_collision_shape()


func _build_village() -> void:
	var builder := VillageBuilder.new(_layout, _terrain, _materials)
	_village_root.add_child(builder.build_village())
	_sky_rig.set("village_materials", _materials)
	GameLog.info(TAG, "village — %s" % builder.summary())


func _build_inhabitants(config: GameConfig, population: int) -> void:
	var pop_clamped := clampi(population, 0, NpcRoster.MAX_POPULATION)
	var records := NpcRoster.build(pop_clamped)
	var places := VillageNpcPlaces.build(_layout, records)
	var obstacles := VillageNpcPlaces.build_obstacles(_layout)
	var route_graph := NpcRouteGraph.new(places, _layout.roads, obstacles)
	_npc_system = NpcSimulationSystem.new(records, places, route_graph)
	_npc_system.initialize(Game.get_tick())
	if not Game.set_npc_system(_npc_system):
		push_error("MainWorld: the NPC system could not be registered with Game.")
	for problem in _npc_system.validate():
		GameLog.warning(TAG, "inhabitants — %s" % problem)
	_economy_system = EconomySystem.new(
		_npc_system,
		config.starting_village_food,
		config.starting_village_wood,
		config.starting_village_stone,
		config.starting_village_coin
	)
	_economy_system.initialize(Game.get_tick())
	if not Game.set_economy_system(_economy_system):
		push_error("MainWorld: the economy system could not be registered with Game.")
	for problem in _economy_system.validate():
		GameLog.warning(TAG, "economy — %s" % problem)
	_npc_presenter.configure(
		_npc_system, _terrain, _player, config.npc_view_distance
	)
	GameLog.info(
		TAG,
		"inhabitants — %s; %s" % [_npc_system.summary(), _npc_system.validate()]
	)
	GameLog.info(TAG, "economy — %s" % _economy_system.summary())
	_build_social_layer(config)


func _build_social_layer(config: GameConfig) -> void:
	_social_system = SocialSystem.new(_npc_system, _economy_system)
	_social_system.configure(
		config.social_memory_capacity,
		config.social_memory_importance_floor,
		config.social_event_log_limit,
		config.social_interaction_radius,
		config.social_cooldown_ticks,
		config.social_daily_gain_cap
	)
	_social_system.initialize(Game.get_tick())
	if not Game.set_social_system(_social_system):
		push_error("MainWorld: the social system could not be registered with Game.")
	for problem in _social_system.validate():
		GameLog.warning(TAG, "social — %s" % problem)
	GameLog.info(TAG, "social — %s" % _social_system.summary())


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


func _publish_area() -> void:
	if _areas == null or _player == null:
		return
	var flat := Vector2(_player.global_position.x, _player.global_position.z)
	var area := _areas.area_at(flat)
	if area != _current_area:
		_current_area = area
		EventBus.area_changed.emit(area)


func _add_save_panel() -> void:
	# Only add once.
	if has_node("SavePanel"):
		return
	var panel := SaveLoadPanel.new()
	panel.name = "SavePanel"
	add_child(panel)


func _build_summary() -> String:
	# Relief, worst open-ground step and horizon rise are measured on the same
	# grid the mesh and the heightmap use: if a future change flattens the
	# landscape or smuggles in a cliff, the boot log says so.
	var span := _terrain.height_range()
	var message := "MainWorld ready — terrain %dx%d cells (%.0f x %.0f u, %d tris), "
	message += "relief %.1f m (worst open step %.2f m, horizon +%.2f m), "
	message += "%d named areas, %d inhabitants, spawn %s"
	return message % [
		_terrain.size_cells,
		_terrain.size_cells,
		_terrain.get_extent(),
		_terrain.get_extent(),
		_terrain.get_triangle_count(),
		span.y - span.x,
		_terrain.max_neighbour_step(true),
		_terrain.horizon_rise(),
		_areas.get_area_count(),
		_npc_system.get_record_count() if _npc_system != null else 0,
		_player.global_position,
	]
