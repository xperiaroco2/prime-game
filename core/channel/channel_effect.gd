class_name ChannelEffect
extends RuleEffect
## The base of an effect that starts a channel (ARCHITECTURE §9.4; M4-4): an action that takes
## `seconds` of the actor holding it, such as the raise. Run as the effect of an action (a rule on
## an intent), it starts a Channel for the actor on the intent's `target` (a player, or none) and
## calls started(). ChannelTicks then advances it every tick and checks the rule's conditions again
## each time (Channels.advance): the first that fails stops it, and so do the stops of Channels
## (an applied action of its actor, its actor or target leaving, being hit, downed or dying; §9.2).
## When it has run `seconds` it completes. A subclass says what its start, stop and completion do
## and emit; this class emits nothing itself.
##
## A phase that accepts an intent whose rule holds a ChannelEffect lists ChannelTicks, or the mode
## check refuses the phase: the channel would never complete (§9.1). The rule's conditions must
## read the target through Channels.target_of, since no intent is handled while they are checked
## again; a condition on the intent's item (InReach) would fail every tick.

## Seconds the actor holds it, 0.05 to 600. The neutral default is out of bounds on purpose: the
## data sets it (the base mode's raise: 3), so the mode check refuses a rule that forgot it.
@export var seconds := 0.0


## Starts the actor's channel, then started(). An actor that runs one already (a rule without
## ChannelFree) is a rule error, logged, and nothing starts.
func run(ctx: MatchContext) -> void:
	if ctx.actor_state() == null or ctx.command == null:
		ctx.error("%s: a channel starts only from a player's intent" % _name())
		return
	if Channels.of_actor(ctx.state, ctx.actor) != null:
		ctx.error("%s: player %d runs a channel already" % [_name(), ctx.actor])
		return
	var channel := Channel.new()
	channel.effect = self
	channel.rule = ctx.rule
	channel.actor = ctx.actor
	channel.target = Channels.target_of(ctx)
	channel.started_tick = ctx.tick
	channel.total_ticks = maxi(1, Ticks.from_seconds(seconds))
	Channels.add(ctx.state, channel)
	var own := ctx.copy()
	own.channel = channel
	started(own, channel)


## Whether a running channel of this effect holds its target in place (the raise: the downed
## player's claims may not move it, MovementRule). False by default.
func holds_target() -> bool:
	return false


## `channel` started (it is running already). Nothing by default.
func started(_ctx: MatchContext, _channel: Channel) -> void:
	pass


## `channel` stopped before completing: a condition failed, or one of Channels' stops. It is no
## longer running. Nothing by default.
func stopped(_ctx: MatchContext, _channel: Channel) -> void:
	pass


## `channel` ran its time and completed. It is no longer running. Nothing by default.
func completed(_ctx: MatchContext, _channel: Channel) -> void:
	pass


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(found, [out_of_bounds("%s seconds" % _name(), seconds, 0.05, 600)])
	return found


func _name() -> String:
	var script := get_script() as Script
	var global := script.get_global_name() if script != null else &""
	return String(global) if not global.is_empty() else "ChannelEffect"
