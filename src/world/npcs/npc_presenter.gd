class_name NpcPresenter
extends Node3D
## The optional 3D representation of the NPC simulation.
##
## It is an observer, not a participant: it reads [NpcRecord]s, creates
## articulated procedural 3D character views for the ones near the player, frees
## the views of the ones far away — and never writes to a record. The simulation
## keeps updating every inhabitant regardless of [member render_distance].
##
## Visual & animation model:
## * Geometry and materials are built by [NpcVisualFactory] from shared
##   low-poly primitives (legs, boots, tunic skirt, belt with buckle, torso,
##   collar, arms with hands, head with facial orientation cues, hair and
##   profession-specific garments, headgear and packs).
## * Because EVERAFTER is a text-only repository without imported `.glb`/`.fbx`
##   skeletal assets or keyframe `AnimationPlayer` clips, motion is procedural:
##   heading turns use `lerp_angle` and limb/torso pivots interpolate smoothly
##   between walking strides and activity postures (`WORKING`, `EATING`,
##   `SOCIALIZING`, `RESTING`, `SLEEPING`, `IDLE`, `BLOCKED`).
##
## Selection is real: a ray from the camera (crosshair when the mouse is
## captured, pointer when it is free) hits the character's `StaticBody3D` and
## publishes `EventBus.npc_selected`. The UI panel and the selected ring/beacon
## react to the same event, so the list and the world can never disagree.

const NPC_COLLISION_LAYER := 1 << 3
const RAY_LENGTH := 160.0
const SNAP_DISTANCE := 10.0
const BODY_HEIGHT := 1.72
const BODY_RADIUS := 0.32
const TURN_SPEED := 10.5
const POSE_BLEND_SPEED := 9.0
const WALK_PHASE_RATE := 5.6
const ACTIVITY_PHASE_RATE := 3.2

## Distance at which an inhabitant gets a view. Configurable from
## `GameConfig.npc_view_distance` and overridable by tests.
@export var render_distance: float = 70.0

var _system: NpcSimulationSystem = null
var _terrain: TerrainGenerator = null
var _player: Node3D = null
var _views: Dictionary = {}
var _view_states: Dictionary = {}
var _selected_id: String = ""
var _visual_factory: NpcVisualFactory = null
var _pulse_time: float = 0.0


func _ready() -> void:
	EventBus.npc_selected.connect(_on_npc_selected)
	if _visual_factory == null:
		_visual_factory = NpcVisualFactory.new()


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
	if _visual_factory == null:
		_visual_factory = NpcVisualFactory.new()


func _process(delta: float) -> void:
	_pulse_time += delta
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
	# use the click position, so clicking a villager in the world works even if
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


func get_visual_factory() -> NpcVisualFactory:
	if _visual_factory == null:
		_visual_factory = NpcVisualFactory.new()
	return _visual_factory


## Lets a test (or a quality setting) change the culling distance at runtime.
func set_render_distance(distance: float) -> void:
	render_distance = maxf(distance, 0.0)


## Clears all character views so they are rebuilt from the current records on
## the next frame. Called by MainWorld after a save is loaded.
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
		var is_selected := record.id == _selected_id
		var should_render := distance <= render_distance or is_selected
		if not should_render:
			_free_view(record.id)
			continue
		var node := _views.get(record.id, null) as Node3D
		var was_created := false
		if node == null:
			node = _create_view(record)
			_views[record.id] = node
			was_created = true
		var move_ratio := _update_transform(node, record, visual_speed, delta, was_created)
		_update_procedural_pose(node, record, move_ratio, delta)
		_update_selection_visuals(node, record, is_selected)


func _update_transform(
	node: Node3D,
	record: NpcRecord,
	visual_speed: float,
	delta: float,
	was_created: bool
) -> float:
	var target := _world_position(record.position)
	if was_created:
		node.position = target
		if record.has_destination:
			var to_dest := record.destination - record.position
			if to_dest.length_squared() > 0.001:
				node.rotation.y = atan2(-to_dest.x, -to_dest.y)
		return 0.0
	var previous := node.position
	var max_step := visual_speed * maxf(delta, 0.0001)
	node.position = node.position.move_toward(target, max_step)
	if node.position.distance_to(target) > SNAP_DISTANCE:
		node.position = target
	var moved := node.position - previous
	var flat_moved := Vector2(moved.x, moved.z).length()
	if flat_moved > 0.0005:
		var desired_yaw := atan2(-moved.x, -moved.z)
		var turn_weight := clampf(delta * TURN_SPEED, 0.0, 1.0)
		node.rotation.y = lerp_angle(node.rotation.y, desired_yaw, turn_weight)
	return clampf(flat_moved / maxf(max_step, 0.001), 0.0, 1.2)


func _update_procedural_pose(
	node: Node3D, record: NpcRecord, move_ratio: float, delta: float
) -> void:
	var state: Dictionary = _view_states.get(record.id, {})
	if state.is_empty():
		state = {
			"phase": float(absi(record.id.hash()) % 100) * 0.06,
			"scale": NpcVisualFactory.stature_scale_for(record.id, record.age),
		}
	var phase := float(state.get("phase", 0.0))
	var time_factor := clampf(Game.get_time_scale(), 0.5, 3.0)
	if Game.is_paused():
		time_factor = 0.0
	if move_ratio > 0.08 or record.activity == NpcRecord.Activity.WALKING:
		phase += delta * WALK_PHASE_RATE * maxf(move_ratio, 0.7) * maxf(time_factor, 0.5)
	else:
		phase += delta * ACTIVITY_PHASE_RATE * maxf(time_factor, 0.35)
	state["phase"] = fmod(phase, TAU * 64.0)
	_view_states[record.id] = state

	var rig := node.get_node_or_null("BodyRig") as Node3D
	if rig == null:
		return
	var targets := NpcVisualFactory.compute_pose_targets(
		record.activity, phase, move_ratio
	)
	var blend := clampf(delta * POSE_BLEND_SPEED, 0.0, 1.0)
	var base_scale: Vector3 = state.get("scale", Vector3.ONE)
	rig.position.y = lerpf(rig.position.y, float(targets["bob_y"]) * base_scale.y, blend)

	var torso := rig.get_node_or_null("TorsoPivot") as Node3D
	if torso != null:
		torso.rotation.x = lerpf(torso.rotation.x, float(targets["torso_pitch"]), blend)
		torso.rotation.z = lerpf(torso.rotation.z, float(targets["torso_roll"]), blend)
		torso.rotation.y = lerpf(torso.rotation.y, float(targets["torso_yaw"]), blend)
		var head := torso.get_node_or_null("HeadPivot") as Node3D
		if head != null:
			head.rotation.x = lerpf(head.rotation.x, float(targets["head_pitch"]), blend)
			head.rotation.y = lerpf(head.rotation.y, float(targets["head_yaw"]), blend)
		var left_arm := torso.get_node_or_null("LeftArm") as Node3D
		if left_arm != null:
			left_arm.rotation.x = lerpf(
				left_arm.rotation.x, float(targets["left_arm_pitch"]), blend
			)
			left_arm.rotation.z = lerpf(
				left_arm.rotation.z, float(targets["left_arm_roll"]), blend
			)
		var right_arm := torso.get_node_or_null("RightArm") as Node3D
		if right_arm != null:
			right_arm.rotation.x = lerpf(
				right_arm.rotation.x, float(targets["right_arm_pitch"]), blend
			)
			right_arm.rotation.z = lerpf(
				right_arm.rotation.z, float(targets["right_arm_roll"]), blend
			)
	var left_leg := rig.get_node_or_null("LeftLeg") as Node3D
	if left_leg != null:
		left_leg.rotation.x = lerpf(
			left_leg.rotation.x, float(targets["left_leg_pitch"]), blend
		)
	var right_leg := rig.get_node_or_null("RightLeg") as Node3D
	if right_leg != null:
		right_leg.rotation.x = lerpf(
			right_leg.rotation.x, float(targets["right_leg_pitch"]), blend
		)


func _update_selection_visuals(
	node: Node3D, record: NpcRecord, is_selected: bool
) -> void:
	var ring := node.get_node_or_null("SelectedRing") as Node3D
	if ring != null:
		ring.visible = is_selected
		if is_selected:
			var pulse := 1.0 + sin(_pulse_time * 3.8) * 0.055
			ring.scale = Vector3(pulse, 1.0, pulse)
			var beacon := ring.get_node_or_null("SelectionBeacon") as Node3D
			if beacon != null:
				beacon.position.y = (
					NpcVisualFactory.BASE_HEIGHT + 0.50 + sin(_pulse_time * 3.8) * 0.04
				)
				beacon.rotation.y = _pulse_time * 1.4
	var name_label := node.get_node_or_null("NameLabel") as Label3D
	if name_label != null:
		name_label.modulate = (
			Color(1.0, 0.92, 0.62, 1.0)
			if is_selected
			else Color(0.95, 0.91, 0.82, 0.92)
		)
	var role_label := node.get_node_or_null("RoleLabel") as Label3D
	if role_label != null:
		role_label.visible = is_selected
		if is_selected:
			role_label.text = "%s · %s" % [
				record.profession_label, record.activity_label()
			]


func _visual_speed() -> float:
	var tick_seconds := maxf(Game.config.logic_tick_seconds, 0.001)
	var speed := NpcSimulationSystem.WALK_DISTANCE_PER_TICK / tick_seconds
	return maxf(speed * Game.get_time_scale() * 1.7, 4.0)


func _create_view(record: NpcRecord) -> Node3D:
	if _visual_factory == null:
		_visual_factory = NpcVisualFactory.new()
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
	_visual_factory.populate_character_view(
		body, record, record.id == _selected_id
	)
	add_child(body)
	return body


func _free_view(npc_id: String) -> void:
	_view_states.erase(npc_id)
	if not _views.has(npc_id):
		return
	var node := _views[npc_id] as Node3D
	_views.erase(npc_id)
	if node != null:
		node.queue_free()


func _world_position(flat: Vector2) -> Vector3:
	return Vector3(flat.x, _terrain.height_at(flat.x, flat.y), flat.y)


func _on_npc_selected(npc_id: String) -> void:
	if npc_id.is_empty():
		_selected_id = ""
		return
	if _system != null and _system.get_record(npc_id) != null:
		_selected_id = npc_id
