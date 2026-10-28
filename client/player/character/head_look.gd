class_name HeadLook
extends SkeletonModifier3D
## The head follows the aim (#1334, ARCHITECTURE §4.7.53): a child of the character's Skeleton3D
## that runs after the AnimationTree, on top of any clip, and turns the Neck and Head bones by the
## aim against the body (aim_yaw, positive to the left) and its pitch (aim_pitch, positive up),
## clamped to the art's limits; the meshes follow the bones, nothing else moves. Written for this
## repo from the art handoff's spec (prime-game-art#196): the engine's LookAtModifier3D and
## AimModifier3D aim one bone at a target node, while this takes two numbers from the network
## pose, splits them over two bones and clamps yaw and pitch apart.
##
## body_follow() is the body's lag (the engineer's 45-degree dead zone): the body keeps its yaw
## while the aim is within the zone of it and turns to hold the aim on the zone's edge beyond it.

## The clamps, radians (the art's: yaw +-70, pitch up 40, down 35 degrees).
const MAX_YAW := deg_to_rad(70.0)
const MAX_PITCH_UP := deg_to_rad(40.0)
const MAX_PITCH_DOWN := deg_to_rad(35.0)
## The bones, and the Neck's share of the turn (the Head takes the rest). The split is a
## placeholder, "not a decision" (the engineer's playtest tunes it).
const NECK := &"Neck"
const HEAD := &"Head"
const NECK_SHARE := 0.5

## The aim against the body, radians: yaw positive to the body's left, pitch positive up.
var aim_yaw := 0.0
var aim_pitch := 0.0
## The skeleton's basis in the body's frame (the frame faces -Z, +X its right, +Y up): the turn
## is built in that frame and carried into the skeleton's.
var frame := Basis.IDENTITY


## The body's yaw after the aim moved to `aim_world_yaw`: kept while the aim is within
## `dead_zone` of `body_yaw`, else turned so the aim sits on the zone's edge; the wrap at +-PI
## counts the short way round. A broken number keeps the body.
static func body_follow(body_yaw: float, aim_world_yaw: float, dead_zone: float) -> float:
	if not is_finite(body_yaw) or not is_finite(aim_world_yaw):
		return body_yaw
	var off := wrapf(aim_world_yaw - body_yaw, -PI, PI)
	if absf(off) <= dead_zone:
		return body_yaw
	return wrapf(aim_world_yaw - signf(off) * dead_zone, -PI, PI)


## `yaw` and `pitch` within the clamps (Vector2(yaw, pitch)); a broken number is 0.
static func clamped(yaw: float, pitch: float) -> Vector2:
	var y := clampf(yaw, -MAX_YAW, MAX_YAW) if is_finite(yaw) else 0.0
	var p := clampf(pitch, -MAX_PITCH_DOWN, MAX_PITCH_UP) if is_finite(pitch) else 0.0
	return Vector2(y, p)


## The turn of `share` of the clamped aim in the body's frame: the yaw about up, then the pitch
## about the turned right axis (the camera's order).
static func turn_of(yaw: float, pitch: float, share := 1.0) -> Basis:
	var aim := clamped(yaw, pitch) * share
	return Basis(Vector3.UP, aim.x) * Basis(Vector3.RIGHT, aim.y)


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	# The Head inherits the Neck's turn, so it adds only what is left of the whole aim: with yaw
	# and pitch together two half turns would not make the aim's turn (they leave a roll).
	var neck := turn_of(aim_yaw, aim_pitch, NECK_SHARE)
	_turn(skeleton, skeleton.find_bone(NECK), neck)
	_turn(skeleton, skeleton.find_bone(HEAD), turn_of(aim_yaw, aim_pitch) * neck.inverse())


## Turns `bone` about its own origin by `body_turn` (in the body's frame), in the skeleton's space.
func _turn(skeleton: Skeleton3D, bone: int, body_turn: Basis) -> void:
	if bone < 0:
		return
	var turn := frame.inverse() * body_turn * frame
	var pose := skeleton.get_bone_global_pose(bone)
	skeleton.set_bone_global_pose(bone, Transform3D(turn * pose.basis, pose.origin))
