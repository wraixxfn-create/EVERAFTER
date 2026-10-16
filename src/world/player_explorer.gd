class_name PlayerExplorer
extends CharacterBody3D
## First person explorer for the village.
##
## Deliberately a plain `CharacterBody3D` + capsule and nothing more: this phase
## has to prove that the world is solid underfoot, and `move_and_slide()` against
## the terrain heightmap and the building colliders is the native, well tested
## way to do that. No custom kinematics, no camera-only movement, no invented
## collision code.
##
## Two clocks are at work and they are independent on purpose:
## * movement runs in `_physics_process` (fixed step) so collisions stay stable;
## * the *simulation* runs on its own tick rate in `SimulationLoop`.
##
## Mouse handling, because it is the part that annoys players when it is wrong:
## * the mouse starts captured;
## * `Esc` always gives the mouse back (to reach the window, the editor, a
##   second screen) and never kills the process;
## * a left click or `F` takes it back, and `EventBus.mouse_capture_changed`
##   lets the HUD say so on screen instead of leaving the player guessing;
## * losing window focus releases the mouse, so alt-tabbing does not trap it.

## How far from the terrain border the player is stopped.
const CAPTURE_DISTANCE_FROM_EDGE := 2.0

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 9.0
@export var jump_velocity: float = 6.0
@export var mouse_sensitivity: float = 0.0022
@export var acceleration: float = 45.0
@export var deceleration: float = 32.0
@export_range(30.0, 89.0) var max_pitch_degrees: float = 85.0
## Half width of the walkable world. The player is kept inside it, so walking
## off the edge of the terrain is impossible rather than merely unlikely.
@export var world_half_extent: float = 63.5

var _gravity: float = 9.8
var _pitch_radians: float = 0.0
var _mouse_captured := false

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	floor_stop_on_slope = true
	if _camera != null:
		_camera.current = true
	set_mouse_captured(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		_apply_look((event as InputEventMouseMotion).relative)
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not _mouse_captured:
			set_mouse_captured(true)
		return
	# Escape only ever releases: a key that both captures and releases is a trap
	# for anyone who pressed it by accident.
	if event.is_action_pressed("ui_cancel"):
		if _mouse_captured:
			set_mouse_captured(false)
	elif event.is_action_pressed("capture_mouse"):
		if not _mouse_captured:
			set_mouse_captured(true)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_direction := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	# The body carries the yaw only (pitch lives on `Head`), so this direction is
	# already horizontal: looking up or down never changes where "forward" is.
	var direction := (global_transform.basis * Vector3(input_direction.x, 0.0, input_direction.y))
	direction = direction.normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var rate := acceleration if direction != Vector3.ZERO else deceleration
	velocity.x = move_toward(velocity.x, direction.x * speed, rate * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, rate * delta)
	move_and_slide()
	_keep_inside_world()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_mouse_captured(false)


func set_mouse_captured(captured: bool) -> void:
	var changed := _mouse_captured != captured
	_mouse_captured = captured
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	)
	if changed:
		EventBus.mouse_capture_changed.emit(captured)


func is_mouse_captured() -> bool:
	return _mouse_captured


## Height of the camera above the body origin, used to place the player on spawn.
func get_eye_height() -> float:
	if _head == null:
		return 0.0
	return _head.position.y


## Turns the player towards a world point. Used at spawn so the village is in
## frame on the very first image instead of behind the player's back.
func look_toward(target: Vector3) -> void:
	var flat := target - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	var yaw := atan2(-flat.x, -flat.z)
	rotation = Vector3(0.0, yaw, 0.0)


# --- internals ---------------------------------------------------------------


func _apply_look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	_pitch_radians = clampf(
		_pitch_radians - relative.y * mouse_sensitivity,
		-deg_to_rad(max_pitch_degrees),
		deg_to_rad(max_pitch_degrees)
	)
	_head.rotation.x = _pitch_radians


## Soft wall at the terrain border. `move_and_slide()` cannot help here: past
## the last heightmap cell there is no geometry at all, only the void.
func _keep_inside_world() -> void:
	var limit := world_half_extent - CAPTURE_DISTANCE_FROM_EDGE
	var clamped_x := clampf(global_position.x, -limit, limit)
	var clamped_z := clampf(global_position.z, -limit, limit)
	if not is_equal_approx(clamped_x, global_position.x) \
			or not is_equal_approx(clamped_z, global_position.z):
		global_position = Vector3(clamped_x, global_position.y, clamped_z)
		velocity.x = 0.0
		velocity.z = 0.0
