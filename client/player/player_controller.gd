class_name PlayerController
extends CharacterBody3D
## The local player's first-person controller (ARCHITECTURE §7 and §7.1), without networking yet:
## it walks, sprints and jumps as `stamina` allows, walks up steps, collides with the other
## living players' kinematic capsules and resolves its own overlap with them (it never moves
## them), and as a ghost flies without gravity through players but not through walls.
## The origin is at the feet. Numbers come from `tuning` only.

## Largest look-up or look-down angle, just short of straight up or down.
const MAX_PITCH := deg_to_rad(89.0)
## Smallest horizontal travel in a step that counts as moving, for stamina (metres).
const MOVE_EPSILON := 0.0001
## Smallest rise that counts as walking up a step rather than along a flat floor (metres).
const STEP_EPSILON := 0.001
## How far above a ledge's top the body crosses its edge, so the capsule's bottom clears it.
const STEP_CLEARANCE := 0.01

@export var tuning: PlayerTuning = preload("res://client/player/player_tuning.tres")
## A ghost flies at `tuning.ghost_speed` without gravity and collides with the level only.
@export var ghost: bool = false:
	set = set_ghost
## Read the keyboard and mouse. Tests turn it off and set the wish fields below themselves.
@export var reads_device_input: bool = true
## Radians of turn per pixel of mouse motion: a player preference, not a game rule.
@export var mouse_sensitivity: float = 0.0025

## What the player wants this physics step. `move_input.y` is forward, `move_input.x` right.
var move_input: Vector2 = Vector2.ZERO
var sprint_held: bool = false
## Set when jump is pressed; the next physics step consumes it, jumping or not.
var jump_requested: bool = false
## A ghost's vertical flight.
var fly_up_held: bool = false
var fly_down_held: bool = false
## Asked before a sprint or a jump, told what each step spent. Defaults to the local stand-in.
var stamina: StaminaSource

var _sprinting: bool = false
## Feet height when the body last stood on a floor: what a step's height is measured from.
var _floor_y: float = 0.0
## True while crossing a ledge's edge after `_step_up`: no gravity, and it counts as grounded.
var _stepping: bool = false
## Horizontal metres the current crossing may still take before gravity returns.
var _step_left: float = 0.0

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	if stamina == null:
		stamina = LocalStamina.new(tuning)
	_apply_tuning()
	set_ghost(ghost)
	_floor_y = global_position.y


func _physics_process(delta: float) -> void:
	if reads_device_input:
		_read_device_input()
	if ghost:
		_fly(delta)
	else:
		_walk(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not reads_device_input:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var motion := event as InputEventMouseMotion
	if motion != null and captured:
		look(
			-motion.screen_relative.x * mouse_sensitivity,
			-motion.screen_relative.y * mouse_sensitivity
		)
	elif event is InputEventMouseButton and event.is_pressed() and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()


## Turns the body by `yaw` and tilts the head by `pitch`, both in radians.
func look(yaw: float, pitch: float) -> void:
	rotate_y(yaw)
	_head.rotation.x = clampf(_head.rotation.x + pitch, -MAX_PITCH, MAX_PITCH)


## Switches between the living body and a ghost. A ghost is on the ghost layer and collides with
## the level only (Q6), so the living never bump into it and it never bumps into players.
func set_ghost(value: bool) -> void:
	ghost = value
	collision_layer = PhysicsLayers.GHOSTS if ghost else PhysicsLayers.LIVING
	collision_mask = (PhysicsLayers.WORLD if ghost else PhysicsLayers.WORLD | PhysicsLayers.LIVING)
	motion_mode = MOTION_MODE_FLOATING if ghost else MOTION_MODE_GROUNDED
	velocity = Vector3.ZERO
	_sprinting = false
	_stepping = false


## Whether the player is in the sprint state (for the HUD and tests).
func is_sprinting() -> bool:
	return _sprinting


func get_camera() -> Camera3D:
	return _camera


func _apply_tuning() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = tuning.capsule_radius
	capsule.height = tuning.capsule_height
	_shape.shape = capsule
	_shape.position = Vector3(0.0, tuning.capsule_height * 0.5, 0.0)
	_head.position = Vector3(0.0, tuning.eye_height, 0.0)
	floor_snap_length = tuning.step_height


func _read_device_input() -> void:
	move_input = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	sprint_held = Input.is_action_pressed("sprint")
	if Input.is_action_just_pressed("jump"):
		jump_requested = true
	fly_up_held = Input.is_action_pressed("jump")
	fly_down_held = Input.is_action_pressed("fly_down")


func _walk(delta: float) -> void:
	var grounded := is_on_floor() or _stepping
	_sprinting = sprint_held and stamina.can_sprint(_sprinting)
	var speed := tuning.sprint_speed if _sprinting else tuning.walk_speed
	var wish := _horizontal_wish() * speed
	velocity.x = wish.x
	velocity.z = wish.z
	var jumped := false
	var gravity := get_gravity().length()
	if jump_requested and grounded and stamina.can_jump():
		velocity.y = tuning.jump_velocity(gravity, delta)
		jumped = true
		_stepping = false
	elif not grounded:
		velocity.y -= gravity * delta
	jump_requested = false
	var start := global_position
	if grounded and not jumped and _step_up(Vector3(wish.x, 0.0, wish.z) * delta):
		_stepping = true
		_step_left = tuning.capsule_radius * 2.0
	if _stepping:
		velocity.y = 0.0
	move_and_slide()
	var moved := Vector2(global_position.x - start.x, global_position.z - start.z).length()
	if _stepping:
		_cross_step(moved)
	if is_on_floor():
		_floor_y = global_position.y
	stamina.report(delta, _sprinting and moved > MOVE_EPSILON, jumped)


## Starts walking up a ledge that blocks `motion`: lifts the body to just above the ledge's top
## and returns true, or returns false when there is no such ledge. `move_and_slide` then carries
## the body across.
func _step_up(motion: Vector3) -> bool:
	var top := _ledge_top(motion)
	if is_nan(top):
		return false
	global_position.y = top + STEP_CLEARANCE
	return true


## The top of a ledge no higher than `tuning.step_height` above the last floor that blocks
## `motion`, or NAN when there is none. It tries the same motion from just above step height and
## comes down on whatever is below.
func _ledge_top(motion: Vector3) -> float:
	var from := global_transform
	if motion.length_squared() < MOVE_EPSILON * MOVE_EPSILON or not test_move(from, motion):
		return NAN
	var hit := KinematicCollision3D.new()
	var raised := from
	var lift := Vector3(0.0, tuning.step_height + STEP_CLEARANCE, 0.0)
	raised.origin += hit.get_travel() if test_move(raised, lift, hit) else lift
	var ahead := raised
	ahead.origin += hit.get_travel() if test_move(ahead, motion, hit) else motion
	var forward := Vector2(ahead.origin.x - from.origin.x, ahead.origin.z - from.origin.z)
	var down := Vector3(0.0, from.origin.y - ahead.origin.y, 0.0)
	if forward.length() < MOVE_EPSILON or not test_move(ahead, down, hit):
		return NAN
	var top := hit.get_position().y
	var climbable := (
		top - from.origin.y >= STEP_EPSILON
		and top - _floor_y <= tuning.step_height + STEP_EPSILON
		# A low ceiling may have cut the lift short; the crossing height must be clear.
		and top + STEP_CLEARANCE <= raised.origin.y + STEP_EPSILON
	)
	return top if climbable else NAN


## One step of crossing a ledge's edge. The rounded bottom of the capsule would rest on the edge
## as on a steep slope, so the body glides across it without gravity until its bottom is over the
## ledge's top and snaps onto it. The crossing ends early when the player stops or has moved a
## capsule's width without landing; gravity then takes over.
func _cross_step(moved: float) -> void:
	if not is_on_floor():
		apply_floor_snap()
	_step_left -= moved
	if is_on_floor() or moved < MOVE_EPSILON or _step_left <= 0.0:
		_stepping = false


## The wished horizontal direction in world space, at most 1 long.
func _horizontal_wish() -> Vector3:
	var forward := -global_basis.z
	var right := global_basis.x
	var wish := right * move_input.x + forward * move_input.y
	wish.y = 0.0
	return wish.limit_length(1.0)


## A ghost's flight: along the look direction, the strafe and the vertical keys, at ghost speed
## and without gravity. Floating mode slides along walls with no floor logic.
func _fly(_delta: float) -> void:
	var look_basis := _head.global_basis
	var wish := (
		-look_basis.z * move_input.y
		+ look_basis.x * move_input.x
		+ Vector3.UP * (float(fly_up_held) - float(fly_down_held))
	)
	velocity = wish.limit_length(1.0) * tuning.ghost_speed
	jump_requested = false
	move_and_slide()
