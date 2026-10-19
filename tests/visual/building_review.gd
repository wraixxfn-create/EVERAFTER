extends Node3D
## Isolated review scene; does not load saves or alter the live village.
## 1–5: cottage / tall house / longhouse / inn / hall.
## Left/right: orbit; up/down: elevation; wheel: distance.
## F1: front three-quarter; F2: side; F3: rear three-quarter; F4: aerial.

var _camera: Camera3D
var _buildings: Array[Node3D] = []
var _selected := 0
var _azimuth := 0.65
var _elevation := 0.26
var _distance := 12.0


func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("b3c4cc")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("dce3e6")
	settings.ambient_light_energy = 0.3
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	sun.light_color = Color("ffe8c9")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 35.0
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 0.5
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(230.0, 180.0)
	ground.mesh = plane
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("79846a")
	material.roughness = 1.0
	ground.material_override = material
	ground.position = Vector3(44.0, -0.025, 0.0)
	add_child(ground)
	var factory := BuildingFactory.new(VillageMaterials.new(), 17)
	for index in 5:
		var placement := VillageLayout.Placement.new()
		placement.id = "Review_%d" % index
		placement.kind = VillageLayout.KIND_HOUSE
		placement.variant = mini(index, 2)
		placement.scale = 1.0
		if index == 3:
			placement.kind = VillageLayout.KIND_INN
		elif index == 4:
			placement.kind = VillageLayout.KIND_HALL
		var building := factory.build_structure(placement)
		building.position.x = float(index) * 22.0
		add_child(building)
		_buildings.append(building)
	_camera = Camera3D.new()
	_camera.fov = 48.0
	_camera.current = true
	add_child(_camera)
	_update_camera()


func _process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_LEFT):
		_azimuth -= delta * 0.8
	if Input.is_physical_key_pressed(KEY_RIGHT):
		_azimuth += delta * 0.8
	if Input.is_physical_key_pressed(KEY_UP):
		_elevation = minf(_elevation + delta * 0.5, 1.15)
	if Input.is_physical_key_pressed(KEY_DOWN):
		_elevation = maxf(_elevation - delta * 0.5, 0.05)
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_selected = event.keycode - KEY_1
			_distance = 22.0 if _selected == 4 else (19.0 if _selected == 3 else 12.0)
		match event.keycode:
			KEY_F1:
				_azimuth = 0.65
				_elevation = 0.26
			KEY_F2:
				_azimuth = PI * 0.5
				_elevation = 0.16
			KEY_F3:
				_azimuth = PI + 0.65
				_elevation = 0.26
			KEY_F4:
				_azimuth = -0.65
				_elevation = 0.95
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(6.0, _distance - 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(32.0, _distance + 1.0)


func _update_camera() -> void:
	for index in _buildings.size():
		_buildings[index].visible = index == _selected
	var target := _buildings[_selected].position + Vector3(0.0, 3.0, 0.0)
	if _selected == 4:
		target += Vector3(-1.8, 1.8, 0.0)
	_camera.position = (
		target
		+ (
			Vector3(
				sin(_azimuth) * cos(_elevation), sin(_elevation), cos(_azimuth) * cos(_elevation)
			)
			* _distance
		)
	)
	_camera.look_at(target)
