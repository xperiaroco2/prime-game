class_name WheelPoseInRange
extends Condition
## Passes when the intent's `legs` and `arms` name one leg stance and one arm gesture of the mode's
## WheelPoses (ARCHITECTURE §9.4; #1485): a whole pose, one of each. A half pick (one index out of
## range, or missing) and a mode without WheelPoses refuse. Rejects with `no_such_pose`: the sender
## sent the numbers itself, and the lists are the mode's, which every client loads. It reads the
## intent, which a reaction or a win condition has none of, so it keeps reads_actor_state() true.

const NO_SUCH_POSE := &"no_such_pose"


func _test(ctx: MatchContext) -> bool:
	if ctx.command == null or ctx.mode == null or ctx.mode.wheel_poses == null:
		return false
	return ctx.mode.wheel_poses.has_pick(
		ctx.command.get_int("legs", -1), ctx.command.get_int("arms", -1)
	)


func _reason() -> StringName:
	return NO_SUCH_POSE
