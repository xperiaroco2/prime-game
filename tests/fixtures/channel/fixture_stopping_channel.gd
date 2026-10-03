class_name FixtureStoppingChannel
extends FixtureChannel
## A FixtureChannel whose completion then stops every other running channel (Channels.stop_all),
## so a test sees one channel's end end another in the same tick of ChannelTicks.


static func stopping(hold_s: float) -> FixtureStoppingChannel:
	var effect := FixtureStoppingChannel.new()
	effect.seconds = hold_s
	return effect


func completed(ctx: MatchContext, channel: Channel) -> void:
	super.completed(ctx, channel)
	Channels.stop_all(ctx)
