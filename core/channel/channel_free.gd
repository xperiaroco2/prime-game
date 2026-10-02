class_name ChannelFree
extends Condition
## Passes when the actor runs no channel and no channel targets the rule's target
## (Channels.target_of), apart from the channel whose conditions are being checked again
## (ARCHITECTURE §9.4; M4-4): one channel per actor, and one per target, such as one raiser at a
## time (the engineer's answer 4 on PR #133). A rule with no target checks the actor alone.
## Rejects with `busy`: every running channel the base mode has (the raise) is public
## (RaiseStarted), so the sender learns nothing new.

const BUSY := &"busy"


func _test(ctx: MatchContext) -> bool:
	var own := Channels.of_actor(ctx.state, ctx.actor)
	if own != null and own != ctx.channel:
		return false
	var target := Channels.target_of(ctx)
	if target == 0:
		return true
	for channel: Channel in Channels.running(ctx.state):
		if channel.target == target and channel != ctx.channel:
			return false
	return true


func _reason() -> StringName:
	return BUSY
