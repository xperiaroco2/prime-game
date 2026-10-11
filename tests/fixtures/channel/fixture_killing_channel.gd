class_name FixtureKillingChannel
extends FixtureChannel
## A FixtureChannel that kills, for the tests of the kill queue (LifeRules.kill_later and
## settle_kills; the car repair ADR's RE17, #806) and of Strike's skip of a target no longer alive:
## - a stop of the channel of an actor in `queues_on_stop` queues the player it maps to (a car's
##   drop), unless its phase ended (RE4);
## - a stop of the channel of an actor in `kills_on_stop` kills the player it maps to at once (a
##   part that does not wait for the queue);
## - a completion first, with `wins`, adds 1 to peer 0's counter `crew_win` and raises the fact
##   `fixture_done`, so the step records the crew's win (FixtureModes.basic()'s first condition);
##   then it stops the channel of `stops_on_completion` (0: none).

@export var queues_on_stop: Dictionary[int, int] = {}
@export var kills_on_stop: Dictionary[int, int] = {}
@export var wins := false
@export var stops_on_completion := 0


static func killing(hold_s: float) -> FixtureKillingChannel:
	var effect := FixtureKillingChannel.new()
	effect.seconds = hold_s
	return effect


func stopped(ctx: MatchContext, channel: Channel) -> void:
	super.stopped(ctx, channel)
	if channel.phase_ended:
		return
	if queues_on_stop.has(channel.actor):
		LifeRules.kill_later(ctx, queues_on_stop[channel.actor])
	if kills_on_stop.has(channel.actor):
		LifeRules.kill(ctx, kills_on_stop[channel.actor])


func completed(ctx: MatchContext, channel: Channel) -> void:
	super.completed(ctx, channel)
	if wins:
		ctx.state.add_to_counter(0, &"crew_win", 1)
		ctx.raise_fact(Fact.new(&"fixture_done"))
	if stops_on_completion > 0:
		Channels.interrupt(ctx, stops_on_completion)


func emits() -> Array[Script]:
	return [FixtureNoteEvent, DiedEvent, SelfStatusEvent, ItemPlacedEvent]
