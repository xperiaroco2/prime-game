class_name DownedCamera
extends Node3D
## The third-person camera over a downed body (ARCHITECTURE §4.7, the engineer's answer 9 (a) on
## PR #133; the M4 ADR's §3 item 3): for the own player while downed, and for a spectator watching a
## downed target. A SpringArm3D whose pivot (this node) is on the body at the mode's standing eye
## height (the crouched eye's where the standing capsule finds no room, LifeView.downed_eye_of,
## #958), pointing back along the look, with the world layer as its mask and a small sphere, so
## the camera stops before a wall rather than looking through it. The arm never rises above its
## pivot: its pitch is clamped to level or lower, and a look further down tilts the camera alone.
## Placed every frame by its user (place_over(), or place()); the level stays drawn, and
## SightHider hides what the pivot could not see.
##
## Over a body that moves (the knockdown ADR's KE8, ARCHITECTURE §4.7.9) place_over() rises from the
## host's point by the eye height (LifeView.downed_eye_of's: the standing one, or the crouched one
## where the standing capsule finds no room, #958), but never higher than that above the floor below
## the point (a ray down the client's own level), so a body in flight or past a ledge lifts it no
## higher than a player standing under the body would see; and it stops CEILING_MARGIN_M below the
## first world hit straight above. Both rays start a little over the point (a ray that starts on a
## surface may miss it); with no floor below, no floor clamp.

## The arm's length (a placeholder, "not a decision") and the sphere it casts, in metres.
const ARM_LENGTH_M := 2.0
const PROBE_RADIUS_M := 0.2
## The steepest the arm points down behind the body: looking up lowers the camera this far.
const MAX_ARM_PITCH := deg_to_rad(80.0)
## The arm casts in its internal physics step: after LifeView (5) placed the pivot in the same
## step, and before SightHider (10), so a turn or a jump of the pivot never shows the camera at the
## last step's length, through a wall (the reviews of M4-9).
const ARM_PHYSICS_PRIORITY := 7
## How far below the first world hit above the point the pivot stops (KE8: a placeholder, "not a
## decision").
const CEILING_MARGIN_M := 0.1
## How far down the floor ray looks, in metres: deeper than any level (a client constant; a
## placeholder, "not a decision").
const FLOOR_RAY_M := 50.0

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
	_camera.cull_mask = PhotoLayers.LIVE_VIEW
	_arm.add_child(_camera)


## Puts the pivot over the host's `point` of a knocked-down body (KE8, above): `eye_m` the eye
## height (LifeView.downed_eye_of's), `lift_m` how far over the point both rays start (the
## capsule's radius: inside the body, under any ceiling it fits under). Then place(). Called from a
## physics step: it casts.
func place_over(point: Vector3, eye_m: float, lift_m: float, yaw: float, pitch: float) -> void:
	var space := get_world_3d().direct_space_state
	var from := point + Vector3.UP * lift_m
	var below := from + Vector3.DOWN * FLOOR_RAY_M
	var floor_hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, below, PhysicsLayers.WORLD)
	)
	var floor_y: float = (floor_hit["position"] as Vector3).y if not floor_hit.is_empty() else NAN
	var above := point + Vector3.UP * (eye_m + CEILING_MARGIN_M)
	var ceiling_y := NAN
	if above.y > from.y:
		var ceiling_hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, above, PhysicsLayers.WORLD)
		)
		if not ceiling_hit.is_empty():
			ceiling_y = (ceiling_hit["position"] as Vector3).y
	place(clamp_eye(point, eye_m, floor_y, ceiling_y), yaw, pitch)


## The pivot over `point` (KE8): `eye_m` above it, but no higher than `eye_m` above `floor_y` (the
## floor below the point) nor than CEILING_MARGIN_M under `ceiling_y` (the first hit above); NAN:
## none found.
static func clamp_eye(point: Vector3, eye_m: float, floor_y: float, ceiling_y: float) -> Vector3:
	var y := point.y + eye_m
	if not is_nan(floor_y):
		y = minf(y, floor_y + eye_m)
	if not is_nan(ceiling_y):
		y = minf(y, ceiling_y - CEILING_MARGIN_M)
	return Vector3(point.x, y, point.z)


## Puts the pivot at `eye` (place_over()'s clamped eye over the body) and points the arm back
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
