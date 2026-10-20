extends Node3D
## Focused visual review for Visual Polish 19 — the artistic
## composition of the village.
##
## It builds the same deterministic terrain and village as the
## game, then stands the reviewer on the six viewpoints a
## player actually reaches: the spawn (the first frame), the
## plaza centre, the far end of each of the three roads, and
## the pond shore. From there the composition questions of
## the polish are answered by eye: does every road arrive at
## the square, does the market read as a row, does the
## skyline hold all the way around, do the landmarks stay
## visible? No gameplay systems or NPCs are started by this
## scene.

const WORLD_SEED := 20261016
const SIZE_CELLS := 160
const HEIGHT_SCALE := 5.0
## Eye height of the reviewer, the same the player walks at.
const EYE_HEIGHT := 1.7

var _terrain: TerrainGenerator
var _layout: VillageLayout
var _materials: VillageMaterials
var _camera: Camera3D
## What the camera looks at; the orbit controls swing
## around this point.
var _subject := Vector3.ZERO
var _azimuth := 0.5
var _elevation := 0.0
var _distance := 30.0
var _view := 0


func _ready() -> void:
	_materials = VillageMaterials.new()
	_layout = VillageLayout.new(WORLD_SEED, float(SIZE_CELLS - 1) * 0.5)
	_terrain = TerrainGenerator.new(SIZE_CELLS, HEIGHT_SCALE, WORLD_SEED, _layout)
	_build_lighting()
	_build_terrain()
	var builder := VillageBuilder.new(_layout, _terrain, _materials)
	add_child(builder.build_village())
	print(
		"[composition review] %d stalls, %d lamps, %d houses, %d "
		+ "benches, %d planters"
		% [
			_layout.get_placements_of_kind(VillageLayout.KIND_STALL).size(),
			_layout.get_placements_of_kind(VillageLayout.KIND_LAMP).size(),
			_layout.get_placements_of_kind(VillageLayout.KIND_HOUSE).size(),
			_layout.get_placements_of_kind(VillageLayout.KIND_BENCH).size(),
			_layout.get_placements_of_kind(VillageLayout.KIND_FLOWER_BOX).size(),
		]
	)
	print("[composition review] %s" % builder.summary())
	_camera = Camera3D.new()
	_camera.fov = 70.0
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
	_view = posmod(_view, 6)
	# Where the reviewer stands, and what they look at.
	# Every stand point is one the player can reach: the
	# spawn, the square, the end of each road, the shore.
	var stand := Vector3.ZERO
	var look := Vector3.ZERO
	match _view:
		0:
			# The player's first frame: on the south-west
			# road, twenty-two metres out, facing the
			# square.
			stand = _eye_on_road(2, 22.0)
			look = _plaza_center()
			print("[composition review] 1 — the spawn, first frame")
		1:
			# On the plaza rim, looking across the square
			# at the well: orbiting swings the whole rim
			# past the camera, one sector at a time.
			stand = _eye_at(Vector2(10.5, 0.0))
			look = _plaza_center()
			print("[composition review] 2 — plaza rim, square across")
		2:
			stand = _eye_on_road(0, _road_length(0) - 8.0)
			look = _plaza_center()
			print("[composition review] 3 — west road, far end")
		3:
			stand = _eye_on_road(1, _road_length(1) - 8.0)
			look = _plaza_center()
			print("[composition review] 4 — north-east road, far end")
		4:
			stand = _eye_on_road(2, _road_length(2) - 8.0)
			look = _plaza_center()
			print("[composition review] 5 — south-west road, far end")
		5:
			# The pond shore, on the axis that faces the
			# square.
			var shore := (_layout.pond_center - Vector2.ZERO).normalized()
			var bank := _layout.pond_center \
				+ shore * (_layout.pond_radius + 3.0)
			stand = _eye_at(bank)
			look = _plaza_center()
			print("[composition review] 6 — pond shore")
	_subject = look
	_distance = stand.distance_to(look)
	_azimuth = atan2(stand.x - look.x, stand.z - look.z)
	_elevation = atan2(
		stand.y - look.y, max(stand.distance_to(look), 0.001)
	)
	_update_camera()


func _plaza_center() -> Vector3:
	return Vector3(0.0, _terrain.height_at(0.0, 0.0), 0.0)


func _eye_at(point: Vector2) -> Vector3:
	return Vector3(
		point.x, _terrain.height_at(point.x, point.y) + EYE_HEIGHT, point.y
	)


func _eye_on_road(road_index: int, distance: float) -> Vector3:
	return _eye_at(_layout.point_on_road(road_index, distance))


func _road_length(road_index: int) -> float:
	return VillageLayout.polyline_length(_layout.roads[road_index])


func _update_camera() -> void:
	if _camera == null:
		return
	var offset := Vector3(
		sin(_azimuth) * cos(_elevation), sin(_elevation),
		cos(_azimuth) * cos(_elevation)
	) * _distance
	_camera.position = _subject + offset
	_camera.look_at(_subject)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_6:
			_view = event.keycode - KEY_1
			_apply_view()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(1.0, _distance - 2.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(120.0, _distance + 2.0)
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
