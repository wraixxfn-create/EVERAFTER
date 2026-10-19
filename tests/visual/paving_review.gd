extends Node3D
## Visual review scene for the paved surfaces (visual polish 15).
##
## It builds the real village — same seed, same layout, same terrain — but no
## player, no NPCs and no save: only a camera and a sun. That keeps the review
## repeatable and lets you stand exactly where the player would.
##
## 1: eye level on the south road, looking into the square
## 2: the square from the rim, at human height
## 3: aerial three-quarter view of the plaza and the three road mouths
## 4: a doorstep apron, from the road
## 5: the pond road verge, close to the ground
## Left/right orbit, up/down elevation, wheel distance. The camera always looks
## at the same subject, so a defect can be compared between passes.

## The same seed the game uses by default; change it to review another village.
const WORLD_SEED := 20261016
const SIZE_CELLS := 160
const HEIGHT_SCALE := 5.0

var _terrain: TerrainGenerator
var _layout: VillageLayout
var _material: VillageMaterials
var _camera: Camera3D
var _subject := Vector3.ZERO
var _azimuth := 0.0
var _elevation := 0.18
var _distance := 22.0
var _view := 0


func _ready() -> void:
	_material = VillageMaterials.new()
	_layout = VillageLayout.new(WORLD_SEED, float(SIZE_CELLS - 1) * 0.5)
	_terrain = TerrainGenerator.new(SIZE_CELLS, HEIGHT_SCALE, WORLD_SEED, _layout)
	_build_light()
	_build_terrain()
	var builder := VillageBuilder.new(_layout, _terrain, _material)
	var village := builder.build_village()
	add_child(village)
	print("[review] village — %s" % builder.summary())
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.current = true
	add_child(_camera)
	_apply_view()


func _build_light() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("6f93b8")
	sky_material.sky_horizon_color = Color("c9c4b3")
	sky_material.ground_bottom_color = Color("5c5a4c")
	sky_material.ground_horizon_color = Color("b6b09c")
	sky.sky_material = sky_material
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
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
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = _terrain.build_collision_shape()
	body.add_child(shape)
	add_child(body)


func _apply_view() -> void:
	_view = posmod(_view, 5)
	match _view:
		0:
			var point := _layout.point_on_road(2, 24.0)
			_subject = Vector3(0.0, 2.6, 0.0)
			_azimuth = atan2(point.x, point.y)
			_elevation = 0.06
			_distance = 24.0
		1:
			_subject = Vector3(0.0, 1.7, 0.0)
			_azimuth = deg_to_rad(205.0)
			_elevation = 0.10
			_distance = 19.0
		2:
			_subject = Vector3(0.0, 0.0, 0.0)
			_azimuth = deg_to_rad(215.0)
			_elevation = 0.62
			_distance = 40.0
		3:
			var house := _first_door_building()
			if house != null:
				var yaw := deg_to_rad(house.rotation_deg)
				var facing := Vector2(sin(yaw), cos(yaw))
				var front := house.position + facing * 4.4
				_subject = Vector3(house.position.x, 1.2, house.position.y)
				_azimuth = atan2(front.x - house.position.x, front.y - house.position.y)
				_elevation = 0.14
				_distance = 6.5
		4:
			var road_point := _layout.point_on_road(2, 40.0)
			_subject = Vector3(road_point.x, 0.4, road_point.y)
			_azimuth = deg_to_rad(120.0)
			_elevation = 0.05
			_distance = 7.0
	_update_camera()


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
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_view = event.keycode - KEY_1
			_apply_view()
		elif event.keycode == KEY_F5:
			_view = 4
			_apply_view()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(3.0, _distance - 1.5)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(90.0, _distance + 1.5)
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
		_elevation = maxf(_elevation - delta * 0.20, 0.02)
		_update_camera()


func _first_door_building() -> VillageLayout.Placement:
	for placement in _layout.placements:
		if placement.kind == VillageLayout.KIND_HOUSE:
			return placement
	return null
