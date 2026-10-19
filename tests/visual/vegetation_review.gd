extends Node3D
## Visual review scene for the vegetation (visual polish 16).
##
## It builds the real village — same seed, same layout, same terrain — but no
## player, no NPCs and no save: only a camera and a sun. That keeps the review
## repeatable and lets you stand exactly where the player would.
##
## The five views are the five questions the rebuild has to answer:
##
## 1: an oak trunk from arm's length — taper, root flare, real limbs
## 2: a pine crown from below, against the sky — is the silhouette a cone?
## 3: a shrub and a flower patch at knee height — are the details readable?
## 4: the meadow at ground level — tufts, blade shape, patch colour
## 5: the tree line from the village, 55 m out — repetition and mass at range
##
## Left/right orbit, up/down elevation, wheel distance. The camera always looks
## at the same subject, so a defect can be compared between passes. The console
## prints the species/variant tally and the detail split, so a rerun also says
## whether the mix and the triangle budget moved.

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
	add_child(builder.build_village())
	print("[review] village — %s" % builder.summary())
	_report_vegetation()
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.current = true
	add_child(_camera)
	_apply_view()


## Species × variant census, plus how many plants are close enough to the
## village to be built at full detail. Numbers that only change with the seed
## belong here, not in the tests.
func _report_vegetation() -> void:
	var tally := {}
	var placements: Array[VillageLayout.Placement] = []
	for placement in _layout.placements:
		if not VillageLayout.is_vegetation(placement.kind):
			continue
		placements.append(placement)
		var key := "%s v%d" % [placement.kind, placement.variant]
		tally[key] = tally.get(key, 0) + 1
	var builder := VegetationBuilder.new(WORLD_SEED + 7)
	var detailed := 0
	for placement in placements:
		if builder.needs_detail(_layout, placement):
			detailed += 1
	var keys: Array = tally.keys()
	keys.sort()
	print("[review] plants: %d (%d at full detail)" % [placements.size(), detailed])
	for key in keys:
		print("[review]   %-18s %d" % [key, tally[key]])


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
			var oak := _nearest_of_kind(VillageLayout.KIND_TREE_OAK)
			if oak != null:
				_subject = Vector3(oak.position.x, 1.5 * oak.scale, oak.position.y)
				_azimuth = atan2(oak.position.x, oak.position.y) + 0.6
				_elevation = 0.26
				_distance = 5.0
		1:
			var pine := _nearest_of_kind(VillageLayout.KIND_TREE_PINE)
			if pine != null:
				_subject = Vector3(pine.position.x, 6.0 * pine.scale, pine.position.y)
				_azimuth = atan2(pine.position.x, pine.position.y) + 0.4
				# Negative elevation drops the camera to eye height and looks up
				# at the crown: the view that exposes a traffic-cone silhouette.
				_elevation = -0.12
				_distance = 26.0
		2:
			var bush := _nearest_of_kind(VillageLayout.KIND_BUSH)
			if bush != null:
				_subject = Vector3(bush.position.x, 0.55, bush.position.y)
				_azimuth = atan2(bush.position.x, bush.position.y) + 0.9
				_elevation = 0.16
				_distance = 3.4
		3:
			var flowers := _nearest_of_kind(VillageLayout.KIND_FLOWER_PATCH)
			var ground := Vector3.ZERO
			if flowers != null:
				ground = Vector3(flowers.position.x, 0.15, flowers.position.y)
			_subject = ground
			_azimuth = atan2(ground.x, ground.z) + 1.1
			_elevation = 0.12
			_distance = 2.2
		4:
			var center := _tree_line_center()
			var direction := Vector2(center.x, center.z).normalized()
			_subject = Vector3(center.x, 6.0, center.z)
			_azimuth = atan2(direction.x, direction.y) + PI
			_elevation = 0.10
			_distance = 28.0
	_update_camera()


## Where the border forest actually is, so view 5 always looks at trees rather
## than at a random patch of meadow.
func _tree_line_center() -> Vector3:
	var sum := Vector2.ZERO
	var count := 0
	for placement in _layout.placements:
		if not VillageLayout.TREE_KINDS.has(placement.kind):
			continue
		sum += placement.position
		count += 1
	if count == 0:
		return Vector3(0.0, 0.0, 55.0)
	var center := sum / float(count)
	return Vector3(center.x, 0.0, center.y)


func _nearest_of_kind(kind: String) -> VillageLayout.Placement:
	var best: VillageLayout.Placement = null
	var best_distance := 1e9
	for placement in _layout.placements:
		if placement.kind != kind:
			continue
		var distance := placement.position.length()
		if distance < best_distance:
			best_distance = distance
			best = placement
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
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_view = event.keycode - KEY_1
			_apply_view()
		elif event.keycode == KEY_F5:
			_view = 4
			_apply_view()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(1.2, _distance - 1.5)
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
		_elevation = maxf(_elevation - delta * 0.20, -0.25)
		_update_camera()
