class_name PlayerExplorer
extends CharacterBody3D
## Minimal first person explorer: the cheapest robust way to verify that the
## 3D world, the terrain collision and the camera all work together.
##
## Deliberately simple (no crouch, no inventory, no interaction): this phase
## only needs a way to walk around and look at the environment. A proper
## player/possessed-NPC system is a later roadmap item, because it depends on
## the NPC module that does not exist yet.
##
## Movement is intentionally in `_physics_process` (fixed step) so collisions
## stay stable, while the *simulation* uses its own tick rate in
## `SimulationLoop`. The two clocks are independent on purpose.

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 9.0
@export var jump_velocity: float = 6.0
@export var mouse_sensitivity: float = 0.0022
@export var acceleration: float = 40.0
@export var deceleration: float = 30.0
@export_range(30.0, 89.0) var max_pitch_degrees: float = 85.0

var _gravity: float = 9.8
var _pitch_radians: float = 0.0
var _mouse_captured := false

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	if _camera != null:
		_camera.current = true
	set_mouse_captured(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		_apply_look((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not _mouse_captured:
			set_mouse_captured(true)
	elif event.is_action_pressed("ui_cancel"):
		# Escape always gives the mouse back, so the player can reach the editor
		# or the window chrome without killing the process.
		set_mouse_captured(not _mouse_captured)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_direction := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_transform.basis * Vector3(input_direction.x, 0.0, input_direction.y))
	direction = direction.normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var rate := acceleration if direction != Vector3.ZERO else deceleration
	velocity.x = move_toward(velocity.x, direction.x * speed, rate * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, rate * delta)
	move_and_slide()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_mouse_captured(false)


func set_mouse_captured(captured: bool) -> void:
	_mouse_captured = captured
	if captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	return _mouse_captured


## Height of the camera above the ground, used to place the player on spawn.
func get_eye_height() -> float:
	if _head == null:
		return 0.0
	return _head.position.y


func _apply_look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	_pitch_radians = clampf(
		_pitch_radians - relative.y * mouse_sensitivity,
		-deg_to_rad(max_pitch_degrees),
		deg_to_rad(max_pitch_degrees)
	)
	_head.rotation.x = _pitch_radians
