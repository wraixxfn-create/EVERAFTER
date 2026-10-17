class_name NpcPresenter
extends Node3D
## The optional 3D representation of the NPC simulation.
##
## It is an observer, not a participant: it reads [NpcRecord]s, creates simple
## capsule views for the ones near the player, frees the views of the ones far
## away — and never writes to a record. The simulation keeps updating every
## inhabitant regardless of [member render_distance].
##
## Selection is real: a ray from the camera (crosshair when the mouse is
## captured, pointer when it is free) hits the capsule's own `StaticBody3D` and
## publishes `EventBus.npc_selected`. The UI panel and the selected ring react
## to the same event, so the list and the world can never disagree.
##
## The bodies sit on their own collision layer and have an empty collision mask:
## the player walks through them, while the selection ray still sees them.

const NPC_COLLISION_LAYER := 1 << 3
const RAY_LENGTH := 160.0
const SNAP_DISTANCE := 10.0
const BODY_HEIGHT := 1.7
const BODY_RADIUS := 0.32

## Distance at which an inhabitant gets a view. Configurable from
## `GameConfig.npc_view_distance` and overridable by tests.
@export var render_distance: float = 70.0

var _system: NpcSimulationSystem = null
var _terrain: TerrainGenerator = null
var _player: Node3D = null
var _views: Dictionary = {}
var _selected_id: String = ""
var _materials: Dictionary = {}
var _body_mesh: CapsuleMesh = null
var _head_mesh: SphereMesh = null
var _hair_mesh: SphereMesh = null
var _belt_mesh: CylinderMesh = null
var _skin_material: StandardMaterial3D = null
var _belt_material: StandardMaterial3D = null
var _hair_materials: Array[StandardMaterial3D] = []
var _ring_mesh: CylinderMesh = null
var _ring_material: StandardMaterial3D = null


func _ready() -> void:
	EventBus.npc_selected.connect(_on_npc_selected)
	_build_shared_resources()


func configure(
	system: NpcSimulationSystem,
	terrain: TerrainGenerator,
	player: Node3D,
	initial_render_distance: float = 70.0
) -> void:
	_system = system
	_terrain = terrain
	_player = player
	render_distance = maxf(initial_render_distance, 0.0)


func _process(delta: float) -> void:
	if _system == null:
		_system = Game.get_npc_system()
	if _system == null or _terrain == null or _player == null:
		return
	_sync_views(delta)
	if _selected_id != "" and _system.get_record(_selected_id) == null:
		_selected_id = ""
		EventBus.npc_selected.emit("")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("select") or _system == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# Captured mouse: the crosshair is the centre of the screen. Free pointer:
	# use the click position, so clicking a capsule in the village works even if
	# the player captured the mouse with the same click.
	var screen_position := get_viewport().get_visible_rect().size * 0.5
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton:
			screen_position = (event as InputEventMouseButton).position
		else:
			screen_position = get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + direction * RAY_LENGTH, NPC_COLLISION_LAYER
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider := hit.get("collider") as Object
	if collider == null or not collider.has_meta("npc_id"):
		return
	select_npc(String(collider.get_meta("npc_id")))


## Selects an NPC by ID and publishes the choice. Returns false for unknown IDs.
func select_npc(npc_id: String) -> bool:
	if _system == null or _system.get_record(npc_id) == null:
		return false
	_selected_id = npc_id
	EventBus.npc_selected.emit(npc_id)
	return true


func get_selected_id() -> String:
	return _selected_id


func get_view_count() -> int:
	return _views.size()


func get_view_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for key in _views.keys():
		ids.append(String(key))
	return ids


func get_view_node(npc_id: String) -> Node3D:
	return _views.get(npc_id, null) as Node3D


## Lets a test (or a quality setting) change the culling distance at runtime.
func set_render_distance(distance: float) -> void:
	render_distance = maxf(distance, 0.0)


## Clears all capsule views so they are rebuilt from the current records on
## the next frame. Called by MainWorld after a save is loaded: at that point
## record positions can jump (e.g. the NPC was home in the save but a fresh
## build spawned them elsewhere) and stale views must not linger.
func force_refresh() -> void:
	for key in _views.keys():
		_free_view(String(key))
	if _selected_id != "":
		_selected_id = ""
		EventBus.npc_selected.emit("")


# --- internals ---------------------------------------------------------------


func _sync_views(delta: float) -> void:
	var player_position := _player.global_position
	var visual_speed := _visual_speed()
	var records := _system.get_records()
	for record in records:
		var distance := Vector2(
			player_position.x - record.position.x, player_position.z - record.position.y
		).length()
		var should_render := distance <= render_distance or record.id == _selected_id
		if not should_render:
			_free_view(record.id)
			continue
		var node := _views.get(record.id, null) as Node3D
		var was_created := false
		if node == null:
			node = _create_view(record)
			_views[record.id] = node
			was_created = true
		var target := _world_position(record.position)
		if was_created:
			node.position = target
		else:
			var previous := node.position
			node.position = node.position.move_toward(target, visual_speed * delta)
			if node.position.distance_to(target) > SNAP_DISTANCE:
				node.position = target
			var moved := node.position - previous
			if moved.length_squared() > 0.0001:
				node.rotation.y = atan2(-moved.x, -moved.z)
		var ring := node.get_node_or_null("SelectedRing") as Node3D
		if ring != null:
			ring.visible = record.id == _selected_id


func _visual_speed() -> float:
	var tick_seconds := maxf(Game.config.logic_tick_seconds, 0.001)
	var speed := NpcSimulationSystem.WALK_DISTANCE_PER_TICK / tick_seconds
	return maxf(speed * Game.get_time_scale() * 1.7, 4.0)


func _create_view(record: NpcRecord) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "NpcView_%s" % record.id
	body.collision_layer = NPC_COLLISION_LAYER
	body.collision_mask = 0
	body.set_meta("npc_id", record.id)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = BODY_HEIGHT
	shape.shape = capsule
	shape.position.y = BODY_HEIGHT * 0.5
	body.add_child(shape)
	var material := _material_for(record)
	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	torso.mesh = _body_mesh
	torso.material_override = material
	torso.position.y = BODY_HEIGHT * 0.5
	body.add_child(torso)
	# Leather belt: one dark band that breaks the capsule silhouette.
	var belt := MeshInstance3D.new()
	belt.name = "Belt"
	belt.mesh = _belt_mesh
	belt.material_override = _belt_material
	belt.position.y = BODY_HEIGHT * 0.52
	body.add_child(belt)
	var head := MeshInstance3D.new()
	head.name = "Head"
	head.mesh = _head_mesh
	head.material_override = _skin_material
	head.position.y = BODY_HEIGHT + 0.18
	body.add_child(head)
	# Hair cap over the upper half of the head, colour hashed from the id so
	# every villager keeps a stable, personal look.
	var hair := MeshInstance3D.new()
	hair.name = "Hair"
	hair.mesh = _hair_mesh
	hair.material_override = _hair_material_for(record.id)
	hair.position.y = BODY_HEIGHT + 0.30
	body.add_child(hair)
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = record.display_name
	label.font_size = 34
	label.pixel_size = 0.0026
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.outline_size = 5
	label.modulate = Color(0.95, 0.92, 0.82, 1.0)
	label.position.y = BODY_HEIGHT + 0.65
	body.add_child(label)
	var ring := MeshInstance3D.new()
	ring.name = "SelectedRing"
	ring.mesh = _ring_mesh
	ring.material_override = _ring_material
	ring.position.y = 0.02
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = record.id == _selected_id
	body.add_child(ring)
	add_child(body)
	return body


func _free_view(npc_id: String) -> void:
	if not _views.has(npc_id):
		return
	var node := _views[npc_id] as Node3D
	_views.erase(npc_id)
	if node != null:
		node.queue_free()


func _world_position(flat: Vector2) -> Vector3:
	return Vector3(flat.x, _terrain.height_at(flat.x, flat.y), flat.y)


func _material_for(record: NpcRecord) -> StandardMaterial3D:
	var key := record.profession_id
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = record.profession_color
	material.roughness = 0.85
	material.metallic = 0.0
	_materials[key] = material
	return material


func _hair_material_for(npc_id: String) -> StandardMaterial3D:
	return _hair_materials[absi(npc_id.hash()) % _hair_materials.size()]


func _build_shared_resources() -> void:
	_body_mesh = CapsuleMesh.new()
	_body_mesh.radius = BODY_RADIUS
	_body_mesh.height = BODY_HEIGHT
	_body_mesh.radial_segments = 10
	_body_mesh.rings = 4
	_head_mesh = SphereMesh.new()
	_head_mesh.radius = 0.23
	_head_mesh.height = 0.46
	_head_mesh.radial_segments = 10
	_head_mesh.rings = 6
	_hair_mesh = SphereMesh.new()
	_hair_mesh.radius = 0.25
	_hair_mesh.height = 0.28
	_hair_mesh.radial_segments = 10
	_hair_mesh.rings = 5
	_belt_mesh = CylinderMesh.new()
	_belt_mesh.top_radius = BODY_RADIUS + 0.03
	_belt_mesh.bottom_radius = BODY_RADIUS + 0.03
	_belt_mesh.height = 0.12
	_belt_mesh.radial_segments = 10
	_skin_material = StandardMaterial3D.new()
	_skin_material.albedo_color = Color(0.87, 0.68, 0.52)
	_skin_material.roughness = 0.75
	_belt_material = StandardMaterial3D.new()
	_belt_material.albedo_color = Color(0.22, 0.14, 0.09)
	_belt_material.roughness = 0.6
	for hair_color in [
		Color(0.14, 0.10, 0.08), Color(0.34, 0.20, 0.10),
		Color(0.55, 0.41, 0.20), Color(0.70, 0.65, 0.56),
	]:
		var hair := StandardMaterial3D.new()
		hair.albedo_color = hair_color
		hair.roughness = 0.8
		_hair_materials.append(hair)
	_ring_mesh = CylinderMesh.new()
	_ring_mesh.top_radius = 0.72
	_ring_mesh.bottom_radius = 0.72
	_ring_mesh.height = 0.03
	_ring_mesh.radial_segments = 24
	_ring_material = StandardMaterial3D.new()
	_ring_material.albedo_color = Color(0.98, 0.82, 0.32, 0.9)
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _on_npc_selected(npc_id: String) -> void:
	if npc_id.is_empty():
		_selected_id = ""
		return
	if _system != null and _system.get_record(npc_id) != null:
		_selected_id = npc_id
