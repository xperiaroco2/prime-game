class_name PlayerController
extends CharacterBody3D
## The local player's first-person controller (ARCHITECTURE §7 and §7.1), without networking yet:
## it walks, sprints and jumps as `stamina` allows and walks up steps. It never collides with other
## players like a wall: walking into a living player pushes them (the engineer's decision of
## 2026-09-30, #46). This controller moves only its own body: pushing slows it, and a player that
## pushes into it moves it out of the overlap. A ghost moves the same way with the same capsule,
## at `tuning.ghost_speed_factor` times the living's speeds, never limited by stamina, and pushes
## nobody and is pushed by nobody; it collides with the level only (ghosts do not fly). The origin
## is at the feet. Numbers come from `tuning` only.

## Largest look-up or look-down angle, just short of straight up or down.
const MAX_PITCH := deg_to_rad(89.0)
## Smallest horizontal travel in a step that counts as moving, for stamina (metres). A step counts
## only while the player gives movement input: being pushed is not moving by itself.
const MOVE_EPSILON := 0.0001
## Smallest rise that counts as walking up a step rather than along a flat floor (metres).
const STEP_EPSILON := 0.001
## How far above a ledge's top the body crosses its edge, so the capsule's bottom clears it.
const STEP_CLEARANCE := 0.01
## Seconds the view takes to catch up with the body after a step-up lifts it at once.
const VIEW_CATCH_UP_TIME := 0.1
## How far ahead of a ledge's contact point, and from how high above it, the surface under it is
## probed for whether it is walkable (metres).
const SURFACE_PROBE_AHEAD := 0.02
const SURFACE_PROBE_ABOVE := 0.05
## Radians beyond `floor_max_angle` a surface may lean and still count as walkable.
const WALKABLE_SLACK := 0.01
## How far beyond touching another living player's capsule the contact search reaches (metres).
const CONTACT_MARGIN := 0.02

@export var tuning: PlayerTuning = preload("res://client/player/player_tuning.tres")
## A ghost walks, sprints and jumps like the living, at `tuning.ghost_speed_factor` times their
## speeds, never limited by stamina (`stamina` decides that), and collides with the level only.
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
## Asked before a sprint or a jump, told what each step spent. Defaults to the local stand-in.
var stamina: StaminaSource

var _sprinting: bool = false
## Height of the floor surface the body last stood on: what a step's height is measured from.
## Resting on a stair's edge, the rounded bottom puts the feet below that surface.
var _floor_y: float = 0.0
## True while crossing a ledge's edge after `_step_up`: no gravity, and it counts as grounded.
var _stepping: bool = false
## Horizontal metres the current crossing may still take before gravity returns.
var _step_left: float = 0.0
## The contact search for other living players: the capsule, a margin wider.
var _contacts := PhysicsShapeQueryParameters3D.new()

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
	_head.position.y = move_toward(
		_head.position.y, tuning.eye_height, tuning.step_height / VIEW_CATCH_UP_TIME * delta
	)
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
		# The `Input` singleton still sees this click, so `use` (left mouse) reads it as pressed
		# this frame: whoever wires `use` must ignore the click that captured the mouse.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()


## Turns the body by `yaw` and tilts the head by `pitch`, both in radians.
func look(yaw: float, pitch: float) -> void:
	rotate_y(yaw)
	_head.rotation.x = clampf(_head.rotation.x + pitch, -MAX_PITCH, MAX_PITCH)


## Switches between the living body and a ghost. Both collide with the level only: the living
## push each other apart in `_push_apart`, not through collisions. A ghost is on the ghost layer,
## which no push looks at (Q6); it keeps the capsule, gravity, floor and steps of the living.
func set_ghost(value: bool) -> void:
	ghost = value
	collision_layer = PhysicsLayers.GHOSTS if ghost else PhysicsLayers.LIVING
	collision_mask = PhysicsLayers.WORLD
	velocity = Vector3.ZERO
	_sprinting = false
	_stepping = false


## Puts the body at `to` at rest, as a respawn or the host's correction does: no velocity, no
## step in progress, and the new place is the floor a step's height is measured from.
func teleport(to: Transform3D) -> void:
	global_transform = to
	velocity = Vector3.ZERO
	_stepping = false
	_floor_y = to.origin.y
	_head.position.y = tuning.eye_height


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
	var reach := CapsuleShape3D.new()
	reach.radius = tuning.capsule_radius + CONTACT_MARGIN
	reach.height = tuning.capsule_height + CONTACT_MARGIN * 2.0
	_contacts.shape = reach
	_contacts.collision_mask = PhysicsLayers.LIVING
	_contacts.exclude = [get_rid()]


func _read_device_input() -> void:
	move_input = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	sprint_held = Input.is_action_pressed("sprint")
	if Input.is_action_just_pressed("jump"):
		jump_requested = true


func _walk(delta: float) -> void:
	var grounded := is_on_floor() or _stepping
	_sprinting = sprint_held and stamina.can_sprint(_sprinting, ghost)
	var speed := _speed()
	var steering := _horizontal_wish()
	var wish := steering * speed
	if not ghost:
		wish = _push_apart(wish, delta)
	velocity.x = wish.x
	velocity.z = wish.z
	var jumped := false
	var gravity := get_gravity().length()
	if jump_requested and grounded and stamina.can_jump(ghost):
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
		_floor_y = _floor_contact_y()
	# Only the player's own movement costs stamina: a push moves a player that gives no input for
	# free, even while it holds sprint (the engineer's decision of 2026-09-30, #46).
	var moved_itself := moved > MOVE_EPSILON and not steering.is_zero_approx()
	stamina.report(delta, _sprinting and moved_itself, jumped, ghost)


## Metres per second on the ground this step: walk or sprint, of the living or of a ghost.
func _speed() -> float:
	var speed := tuning.sprint_speed if _sprinting else tuning.walk_speed
	return speed * tuning.ghost_speed_factor if ghost else speed


## The horizontal velocity for `wish` among the other living players this body touches. Walking
## into one pushes: the part of `wish` into them slows to `tuning.push_speed_factor`, stops once
## this body is `tuning.push_max_overlap` deep in them, and drifts to the right, so a straight
## head-on push slides off instead of freezing. Every other overlap, one a player pushed into it,
## is left at once: that is how this body is pushed, at the speed the pusher came in. So two
## players pushing each other head-on stop where their pushes meet.
func _push_apart(wish: Vector3, delta: float) -> Vector3:
	_contacts.transform = _shape.global_transform
	var found := get_world_3d().direct_space_state.intersect_shape(_contacts)
	var out := Vector3.ZERO
	for contact: Dictionary in found:
		var other := contact["collider"] as Node3D
		var apart := global_position - other.global_position
		apart.y = 0.0
		var normal := apart.normalized() if apart.length() > MOVE_EPSILON else global_basis.z
		var depth := tuning.capsule_radius * 2.0 - apart.length()
		var allowed := 0.0
		var into := -wish.dot(normal)
		if into > 0.0:
			allowed = tuning.push_max_overlap
			var room := maxf(0.0, allowed - depth) / delta
			var pushed := minf(into * tuning.push_speed_factor, room)
			var right := (-normal).cross(up_direction)
			var drift := into * tuning.push_speed_factor * tuning.push_side_bias
			wish += normal * (into - pushed) + right * drift
		if depth > allowed:
			out += normal * (depth - allowed) / delta
	return wish + out.limit_length(tuning.sprint_speed)


## Starts walking up a ledge that blocks `motion`: lifts the body to just above the ledge's top
## and returns true, or returns false when there is no such ledge. `move_and_slide` then carries
## the body across. Only the body jumps up; the head is lowered by the same amount and eases back
## in `_physics_process`, so the view does not pop on every stair.
func _step_up(motion: Vector3) -> bool:
	var top := _ledge_top(motion)
	if is_nan(top):
		return false
	var lift := top + STEP_CLEARANCE - global_position.y
	global_position.y += lift
	# Sprinting up stairs lifts again before the view has caught up: it lags one step at most.
	_head.position.y = maxf(_head.position.y - lift, tuning.eye_height - tuning.step_height)
	return true


## The top of a ledge no higher than `tuning.step_height` above the last floor that blocks
## `motion`, or NAN when there is none. It tries the same motion from just above step height and
## comes down on whatever is below. What it comes down on must be walkable: the capsule touches a
## steep slope or a round prop below its real top, which is no ledge.
func _ledge_top(motion: Vector3) -> float:
	var from := global_transform
	var hit := KinematicCollision3D.new()
	if motion.length_squared() < MOVE_EPSILON * MOVE_EPSILON or not test_move(from, motion, hit):
		return NAN
	# What blocks the motion is itself walkable, a ramp or a low edge under the rounded bottom:
	# `move_and_slide` walks up it without a lift.
	if _is_walkable(hit.get_normal()):
		return NAN
	var raised := from
	var lift := Vector3(0.0, _floor_y + tuning.step_height + STEP_CLEARANCE - from.origin.y, 0.0)
	raised.origin += hit.get_travel() if test_move(raised, lift, hit) else lift
	var ahead := raised
	ahead.origin += hit.get_travel() if test_move(ahead, motion, hit) else motion
	var forward := Vector2(ahead.origin.x - from.origin.x, ahead.origin.z - from.origin.z)
	var down := Vector3(0.0, from.origin.y - ahead.origin.y, 0.0)
	if forward.length() < MOVE_EPSILON or not test_move(ahead, down, hit):
		return NAN
	var top := hit.get_position().y
	if not _is_walkable_at(hit.get_position(), motion):
		return NAN
	var climbable := (
		top - from.origin.y >= STEP_EPSILON
		and top - _floor_y <= tuning.step_height + STEP_EPSILON
		# A low ceiling may have cut the lift short; the crossing height must be clear.
		and top + STEP_CLEARANCE <= raised.origin.y + STEP_EPSILON
	)
	return top if climbable else NAN


## Whether the surface just past `point` in the direction of `motion` is flat enough to stand on
## (`floor_max_angle`). A ray finds that surface; the capsule's own contact normal at a ledge's
## edge says nothing about the ledge's top.
func _is_walkable_at(point: Vector3, motion: Vector3) -> bool:
	var ahead := Vector3(motion.x, 0.0, motion.z).normalized() * SURFACE_PROBE_AHEAD
	var from := point + ahead + Vector3.UP * SURFACE_PROBE_ABOVE
	var to := from + Vector3.DOWN * SURFACE_PROBE_ABOVE * 4.0
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, [get_rid()])
	var found := get_world_3d().direct_space_state.intersect_ray(query)
	if found.is_empty():
		return true
	return _is_walkable(found["normal"] as Vector3)


## Whether a surface with this normal is flat enough to stand on (`floor_max_angle`, with a
## little slack for a ramp built at exactly that angle).
func _is_walkable(normal: Vector3) -> bool:
	return normal.angle_to(up_direction) <= floor_max_angle + WALKABLE_SLACK


## The highest floor contact of the last `move_and_slide`, or the feet when it reported none.
func _floor_contact_y() -> float:
	var highest := global_position.y
	for i: int in get_slide_collision_count():
		var collision := get_slide_collision(i)
		for j: int in collision.get_collision_count():
			if _is_walkable(collision.get_normal(j)):
				highest = maxf(highest, collision.get_position(j).y)
	return highest


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
