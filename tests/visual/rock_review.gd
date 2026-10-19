extends Node3D
## Focused visual review for Visual Polish 17.
##
## It builds the same deterministic terrain and village as the game, then lets
## the reviewer compare three real placements: a terrain-aligned slope outcrop,
## a pond-side stone and the largest ordinary boulder. No gameplay systems or
## NPCs are started by this scene.

const WORLD_SEED := 20261016
const SIZE_CELLS := 160
const HEIGHT_SCALE := 5.0

var _terrain: TerrainGenerator
var _layout: VillageLayout
var _materials: VillageMaterials
var _builder: VillageBuilder
var _camera: Camera3D
var _subject := Vector3.ZERO
var _azimuth := 0.5
var _elevation := 0.22
var _distance := 4.2
var _view := 0


func _ready() -> void:
	_materials = VillageMaterials.new()
	_layout = VillageLayout.new(WORLD_SEED, float(SIZE_CELLS - 1) * 0.5)
	_terrain = TerrainGenerator.new(SIZE_CELLS, HEIGHT_SCALE, WORLD_SEED, _layout)
	_build_lighting()
	_build_terrain()
	_builder = VillageBuilder.new(_layout, _terrain, _materials)
	add_child(_builder.build_village())
	var status := (
		"[rock review] %d slope outcrops, %d placed stones; "
		+ "controls: 1=slope / 2=pond / 3=boulder, arrows=orbit, wheel=distance."
	)
	print(
		status
		% [
			_builder.slope_outcrop_positions.size(),
			_layout.get_placements_of_kind(VillageLayout.KIND_ROCK).size(),
		]
	)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.current = true
	add_child(_camera)
	_apply_view()


func _build_lighting() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("6f93b8")
	sky_material.sky_horizon_color = Color("c9c4b3")
	sky_material.ground_bottom_color = Color("5c5a4c")
	sky_material.ground_horizon_color = Color("b6b09c")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, -38.0, 0.0)
	sun.light_color = Color("ffe7c6")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 0.5
	add_child(sun)


func _build_terrain() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Terrain"
	mesh.mesh = _terrain.build_mesh()
	mesh.material_override = _terrain.build_material()
	add_child(mesh)


func _apply_view() -> void:
	_view = posmod(_view, 3)
	var point := Vector2.ZERO
	match _view:
		0:
			point = _steepest_outcrop()
			_distance = 4.2
			_elevation = 0.22
			print("[rock review] slope outcrop at %s" % point)
		1:
			point = _pond_side_rock()
			_distance = 3.4
			_elevation = 0.30
			print("[rock review] pond-side stone at %s" % point)
		2:
			point = _largest_placed_rock()
			_distance = 4.0
			_elevation = 0.24
			print("[rock review] large placed boulder at %s" % point)
	_subject = Vector3(point.x, _terrain.height_at(point.x, point.y) + 0.28, point.y)
	_azimuth = atan2(point.x, point.y) + 0.75
	_update_camera()


func _steepest_outcrop() -> Vector2:
	var best := Vector2.ZERO
	var steepest := -1.0
	for point in _builder.slope_outcrop_positions:
		var slope := _terrain.slope_at(point.x, point.y)
		if slope > steepest:
			steepest = slope
			best = point
	return best


func _pond_side_rock() -> Vector2:
	var rocks := _layout.get_placements_of_kind(VillageLayout.KIND_ROCK)
	var best := _layout.pond_center
	var best_distance := INF
	for rock in rocks:
		var distance := rock.position.distance_to(_layout.pond_center)
		if distance < best_distance:
			best_distance = distance
			best = rock.position
	return best


func _largest_placed_rock() -> Vector2:
	var best := _pond_side_rock()
	var best_scale := -1.0
	for rock in _layout.get_placements_of_kind(VillageLayout.KIND_ROCK):
		if rock.scale > best_scale:
			best_scale = rock.scale
			best = rock.position
	return best


func _update_camera() -> void:
	if _camera == null:
		return
	var offset := Vector3(
		sin(_azimuth) * cos(_elevation), sin(_elevation), cos(_azimuth) * cos(_elevation)
	) * _distance
	_camera.position = _subject + offset
	_camera.look_at(_subject)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_3:
			_view = event.keycode - KEY_1
			_apply_view()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(1.2, _distance - 0.5)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(24.0, _distance + 0.5)
			_update_camera()


func _process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_LEFT):
		_azimuth -= delta * 0.35
		_update_camera()
	if Input.is_physical_key_pressed(KEY_RIGHT):
		_azimuth += delta * 0.35
		_update_camera()
	if Input.is_physical_key_pressed(KEY_UP):
		_elevation = minf(_elevation + delta * 0.20, 1.2)
		_update_camera()
	if Input.is_physical_key_pressed(KEY_DOWN):
		_elevation = maxf(_elevation - delta * 0.20, -0.25)
		_update_camera()
