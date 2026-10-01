class_name DownedCamera
extends Node3D
## The third-person camera over a downed body (ARCHITECTURE §4.7, the engineer's answer 9 (a) on
## PR #133; the M4 ADR's §3 item 3): for the own player while downed, and for a spectator watching a
## downed target. A SpringArm3D whose pivot (this node) is on the body at the mode's standing eye
## height, pointing back along the look, with the world layer as its mask and a small sphere, so
## the camera stops before a wall rather than looking through it. The arm never rises above its
## pivot: its pitch is clamped to level or lower, and a look further down tilts the camera alone.
## Placed every frame by its user (place()); the level stays drawn, and SightHider hides what the
## pivot could not see.

## The arm's length (a placeholder, "not a decision") and the sphere it casts, in metres.
const ARM_LENGTH_M := 2.0
const PROBE_RADIUS_M := 0.2
## The steepest the arm points down behind the body: looking up lowers the camera this far.
const MAX_ARM_PITCH := deg_to_rad(80.0)
## The arm casts in its internal physics step: after LifeView (5) placed the pivot in the same
## step, and before SightHider (10), so a turn or a jump of the pivot never shows the camera at the
## last step's length, through a wall (the reviews of M4-9).
const ARM_PHYSICS_PRIORITY := 7

var _arm := SpringArm3D.new()
var _camera := Camera3D.new()


func _init() -> void:
	name = "DownedCamera"
	_arm.name = "Arm"
	_arm.process_physics_priority = ARM_PHYSICS_PRIORITY
	_arm.spring_length = ARM_LENGTH_M
	_arm.collision_mask = PhysicsLayers.WORLD
	var probe := SphereShape3D.new()
	probe.radius = PROBE_RADIUS_M
	_arm.shape = probe
	add_child(_arm)
	_camera.name = "Camera3D"
	_camera.current = false
	_arm.add_child(_camera)


## Puts the pivot at `eye` (the body's feet plus the standing eye height) and points the arm back
## along the look of `yaw` and `pitch` (radians, as a player's): a look up lowers the arm, a look
## down tilts only the camera. Called from a physics step at a priority below
## ARM_PHYSICS_PRIORITY, the arm reaches its new length in the same step.
func place(eye: Vector3, yaw: float, pitch: float) -> void:
	global_position = eye
	rotation = Vector3(0.0, yaw, 0.0)
	var arm_pitch := clampf(pitch, 0.0, MAX_ARM_PITCH)
	_arm.rotation = Vector3(arm_pitch, 0.0, 0.0)
	_camera.rotation = Vector3(pitch - arm_pitch, 0.0, 0.0)


## The body's eye: where SightHider looks from.
func pivot() -> Vector3:
	return global_position


func camera() -> Camera3D:
	return _camera


## The arm's length now, after the last physics step: shorter where the level is in the way.
func arm_length() -> float:
	return _arm.get_hit_length()
