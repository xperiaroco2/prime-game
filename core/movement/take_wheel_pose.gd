class_name TakeWheelPose
extends RuleEffect
## The actor takes the pose wheel's whole pose where it stands (#1485; GDD §8 "Photo", "The pose
## wheel"; ARCHITECTURE §7.1.23, §9.4): the intent's `legs` and `arms` become PlayerState.wheel_legs
## and wheel_arms, which every peer's snapshot shows on its avatar (WheelPoseCode). The rule's
## conditions decide whether it may; a new pick replaces the old one, and the same pick again
## changes nothing. An own move, a crouch or a sneak ends it (MovementRule), as do the chair's
## TakePose, a placement, a knockdown, the limp, a death, a respawn and a reset. As every applied
## action does, it stops the actor's running channel first (RuleRunner). A rule holding it must
## hold WheelPoseInRange (required_conditions, ModeCheck), so only a whole pose of the mode's
## WheelPoses is ever taken.
##
## Emits: nothing (the pose travels in the snapshot, public body state, and to the poser alone in
## its SelfStatus: the touch here makes the end-of-tick flush send it).


func run(ctx: MatchContext) -> void:
	var legs := ctx.command.get_int("legs", -1) if ctx.command != null else -1
	var arms := ctx.command.get_int("arms", -1) if ctx.command != null else -1
	if (
		ctx.mode == null
		or ctx.mode.wheel_poses == null
		or not ctx.mode.wheel_poses.has_pick(legs, arms)
	):
		ctx.error("TakeWheelPose: %d, %d is no pose of the mode (WheelPoseInRange)" % [legs, arms])
		return
	var actor := ctx.state.player(ctx.actor)
	actor.wheel_legs = legs
	actor.wheel_arms = arms
	SelfStatusFeed.touch(ctx.state, ctx.actor)


## The condition classes a rule holding this effect must hold, not negated (ModeCheck):
## WheelPoseInRange, so no mode takes a pose outside its lists.
func required_conditions() -> Array[Script]:
	return [WheelPoseInRange]


func emits() -> Array[Script]:
	return []
