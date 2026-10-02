class_name FixtureChannel
extends ChannelEffect
## A channel that notes its start, stop and completion to everyone ("started 3", "stopped 3 after
## 5", "completed 3 after 20"), so tests see when and how it ended.


static func of(hold_s: float) -> FixtureChannel:
	var effect := FixtureChannel.new()
	effect.seconds = hold_s
	return effect


func started(ctx: MatchContext, channel: Channel) -> void:
	ctx.emit(FixtureNoteEvent.new("started %d" % channel.actor))


func stopped(ctx: MatchContext, channel: Channel) -> void:
	ctx.emit(FixtureNoteEvent.new("stopped %d after %d" % [channel.actor, channel.done_ticks]))


func completed(ctx: MatchContext, channel: Channel) -> void:
	ctx.emit(FixtureNoteEvent.new("completed %d after %d" % [channel.actor, channel.done_ticks]))


func emits() -> Array[Script]:
	return [FixtureNoteEvent]
