class_name Channels
extends RefCounted
## The running channels (ARCHITECTURE §9.1, §9.4; M4-4): the one place that starts, advances,
## stops and completes a Channel. They live in MatchState's per-part state (PART_KEY), at most one
## per actor, so ResetMatch clears them. Every transition stops every running channel before the
## row's actions run (stop_all, Match), so a raise running when Round ends sends its RaiseStopped
## before PhaseChanged and gives its target's knockdown back.
##
## - add(): ChannelEffect.run records a new channel.
## - advance(): ChannelTicks, every tick, for each running channel in actor-id order: the rule's
##   conditions again (not its costs), with the channel in the context and no intent; the first
##   that fails stops it. Else it runs one more tick, and the tick that reaches its time completes
##   it, unless its effect is endless (ChannelEffect.is_endless: the car repair ADR's RE3), which
##   counts its ticks but never completes. The kills a channel's step queued
##   (LifeRules.kill_later: the car's drop) land after that step, before the next channel's (RE17).
## - interrupt(): an applied action of the actor stops its channel first (RuleRunner, §9.2), and so
##   does a hit (LifeRules.damage) when the channel's effect stops on a hit
##   (ChannelEffect.stops_on_hit).
## - interrupt_involving(): a player knocked down, dying or leaving stops every channel it runs or
##   is the target of (LifeRules). A channel on a station (Channel.station, RE2) targets no player.
## - stop_all(): a phase is ending; each channel is marked Channel.phase_ended before its stop
##   (RE4).
## Each stop or completion removes the channel before its effect's stopped() or completed() runs,
## so whatever that does sees it gone.

## Its key in MatchState's per-part state (§9.1).
const PART_KEY := &"channels"


## The running channels by actor.
class Table:
	extends RefCounted
	var by_actor: Dictionary[int, Channel] = {}


## The player an action's channel targets: the channel's, while its conditions are checked again
## or it ends; else the `target` of the intent being handled, when its intent has one (Raise); 0
## when there is none.
static func target_of(ctx: MatchContext) -> int:
	if ctx.channel != null:
		return ctx.channel.target
	if ctx.command == null:
		return 0
	var fields: Dictionary = Intents.FIELDS.get(ctx.command.kind, {})
	return ctx.command.get_int("target", 0) if fields.has("target") else 0


## The placed station's id an action's channel runs on (the car repair ADR's RE2, #805): the
## channel's, while its conditions are checked again or it ends; else the `station` of the intent
## being handled, when its intent has one (Interact); -1 when there is none. The station conditions
## find their station through it (Stations.target_of), as TargetInReach finds its player through
## target_of, so a hold passes its own re-check, where no intent is handled.
static func station_of(ctx: MatchContext) -> int:
	if ctx.channel != null:
		return ctx.channel.station
	if ctx.command == null:
		return -1
	var fields: Dictionary = Intents.FIELDS.get(ctx.command.kind, {})
	return ctx.command.get_int("station", -1) if fields.has("station") else -1


## The channel running on the placed station `station`, or null: at most one (ChannelFree).
static func on_station(state: MatchState, station: int) -> Channel:
	if station < 0:
		return null
	for channel: Channel in running(state):
		if channel.station == station:
			return channel
	return null


## The channel `peer` runs, or null.
static func of_actor(state: MatchState, peer: int) -> Channel:
	return _table(state).by_actor.get(peer)


## The first channel, in actor-id order, that targets `peer`, or null.
static func on_target(state: MatchState, peer: int) -> Channel:
	for channel: Channel in running(state):
		if channel.target == peer:
			return channel
	return null


## Whether a running channel holds `peer` in place (ChannelEffect.holds_target: the raise holds the
## downed player it raises; MovementRule corrects any displacement of its claims).
static func holds(state: MatchState, peer: int) -> bool:
	return holding(state, peer) != null


## The first running channel, in actor-id order, that holds `peer` in place, or null. Its held_at is
## where `peer` is held.
static func holding(state: MatchState, peer: int) -> Channel:
	for channel: Channel in running(state):
		if channel.target == peer and channel.effect.holds_target():
			return channel
	return null


## Every running channel, in actor-id order.
static func running(state: MatchState) -> Array[Channel]:
	var table := _table(state)
	var actors: Array[int] = []
	actors.assign(table.by_actor.keys())
	actors.sort()
	var found: Array[Channel] = []
	for actor: int in actors:
		found.append(table.by_actor[actor])
	return found


## Records `channel` as its actor's running one (ChannelEffect.run).
static func add(state: MatchState, channel: Channel) -> void:
	_table(state).by_actor[channel.actor] = channel


## One tick of every running channel (ChannelTicks).
static func advance(ctx: MatchContext) -> void:
	for channel: Channel in running(ctx.state):
		if of_actor(ctx.state, channel.actor) != channel:
			# Ended meanwhile, by what an earlier channel's end did in this tick.
			continue
		_step(ctx, channel)
		# The kills this channel's step queued land now, before the next channel's step (RE17).
		if LifeRules.kills_queued(ctx.state):
			LifeRules.settle_kills(ctx)


## One channel's step of advance(): its re-check, then one more tick, maybe its completion.
static func _step(ctx: MatchContext, channel: Channel) -> void:
	var own := _context_of(ctx, channel)
	if not _still_holds(own, channel):
		_remove(ctx.state, channel)
		channel.effect.stopped(own, channel)
		return
	channel.done_ticks += 1
	if channel.done_ticks >= channel.total_ticks and not channel.effect.is_endless():
		_remove(ctx.state, channel)
		channel.effect.completed(own, channel)


## Stops the channel `peer` runs, if any.
static func interrupt(ctx: MatchContext, peer: int) -> void:
	var channel := of_actor(ctx.state, peer)
	if channel != null:
		stop(ctx, channel)


## Stops every channel `peer` runs or is the target of, in actor-id order.
static func interrupt_involving(ctx: MatchContext, peer: int) -> void:
	for channel: Channel in running(ctx.state):
		if channel.actor == peer or channel.target == peer:
			stop(ctx, channel)


## Stops every running channel, in actor-id order: a phase is ending (Match's transition), and no
## channel outlives the phase that advanced it. Each is marked phase_ended before its stop, so its
## effect tells the phase's end from a let-go (the car repair ADR's RE4).
static func stop_all(ctx: MatchContext) -> void:
	for channel: Channel in running(ctx.state):
		if of_actor(ctx.state, channel.actor) != channel:
			continue  # Ended meanwhile, by what an earlier channel's stop did.
		channel.phase_ended = true
		stop(ctx, channel)


## Stops the channel `peer` runs when a hit stops it (ChannelEffect.stops_on_hit; LifeRules.damage).
static func interrupt_hit(ctx: MatchContext, peer: int) -> void:
	var channel := of_actor(ctx.state, peer)
	if channel != null and channel.effect.stops_on_hit():
		stop(ctx, channel)


## Stops `channel` before it completes: it is removed, then its effect's stopped() runs.
static func stop(ctx: MatchContext, channel: Channel) -> void:
	if of_actor(ctx.state, channel.actor) != channel:
		return
	_remove(ctx.state, channel)
	channel.effect.stopped(_context_of(ctx, channel), channel)


## Whether every condition of the channel's rule still passes (costs are not checked again).
static func _still_holds(ctx: MatchContext, channel: Channel) -> bool:
	if channel.rule == null:
		return true
	for condition: Condition in channel.rule.conditions:
		if condition is Cost:
			continue
		if not condition.passes(ctx):
			return false
	return true


## A context for `channel`: its actor, its rule, the channel itself, and no intent or fact.
static func _context_of(ctx: MatchContext, channel: Channel) -> MatchContext:
	var own := ctx.copy()
	own.actor = channel.actor
	own.command = null
	own.fact = null
	own.rule = channel.rule
	own.channel = channel
	return own


static func _remove(state: MatchState, channel: Channel) -> void:
	_table(state).by_actor.erase(channel.actor)


static func _table(state: MatchState) -> Table:
	return state.part_state(PART_KEY, func() -> RefCounted: return Table.new()) as Table
