class_name ChannelFree
extends Condition
## Passes when the actor runs no channel, no channel targets the rule's target
## (Channels.target_of) and no channel runs on the rule's station (Channels.station_of), apart from
## the channel whose conditions are being checked again (ARCHITECTURE §9.4; M4-4): one channel per
## actor, one per target, such as one raiser at a time (the engineer's answer 4 on PR #133), and one
## per station, such as one holder of the lift and one fitter at the car (the car repair ADR's RE2,
## RE9). A rule with neither a target nor a station checks the actor alone. Rejects with `busy`:
## every running channel the base mode has (the raise) is public (RaiseStarted), and a station
## channel's task type makes its own public (LiftChanged, FitChanged), so the sender learns nothing
## new.

const BUSY := &"busy"


func _test(ctx: MatchContext) -> bool:
	var own := Channels.of_actor(ctx.state, ctx.actor)
	if own != null and own != ctx.channel:
		return false
	var on_station := Channels.on_station(ctx.state, Channels.station_of(ctx))
	if on_station != null and on_station != ctx.channel:
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
