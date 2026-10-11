class_name AtStation
extends Condition
## Passes when the actor's feet, the position of its last accepted claim (never a position inside
## the intent; ARCHITECTURE §7.1), stand inside the cylinder of the rule's station
## (Stations.target_of: the station the intent names, or on a re-check the channel's;
## StationState.contains: the kind's radius_m and height_m; the Generator ADR's GE3, #796). One
## cylinder means "at the station" for every station: a package rests in it, a zone counts a
## player in it, a switch is used from it. Rejects with `out_of_reach`: the sender knows its own
## position and the station's (StationPlaced is public).
##
## On the re-check of a timed channel on a station (MatchContext.channel set, on a station, its
## effect not endless; the car repair ADR's RE2 with the zone task's ZE10, #805) it also fails when
## the actor's last accepted claim is more than MovementRule.PUSH_TICKS old (or there is none since
## a placement), or the actor stored more than PUSH_TICKS of credit since (MovementRule.credit_gain,
## #647's bound): a timed station channel is presence over time that earns a subtask, so a client
## that stops claiming, or claims too few ticks, stops it, as the zone task stops counting it. The
## endless hold is exempt: a stale holder only keeps its hold, while an honest holder losing half a
## second of claims would drop the car on the fitter.

const OUT_OF_REACH := &"out_of_reach"
## The oldest claim, and the most stored credit, a timed station channel's re-check accepts: the
## push allowance's tolerance, as the zone task's STALE_TICKS.
const STALE_TICKS := MovementRule.PUSH_TICKS


## It needs a station (Stations.target_of), which no fact carries, and also reads the actor (the
## default).
func needs_target() -> bool:
	return true


func _test(ctx: MatchContext) -> bool:
	var actor := ctx.actor_state()
	var station := Stations.target_of(ctx)
	if actor == null or station == null:
		return false
	if not station.contains(actor.position):
		return false
	return not _stale(ctx)


func _reason() -> StringName:
	return OUT_OF_REACH


## Whether this is the re-check of a timed station channel whose actor's position is stale.
static func _stale(ctx: MatchContext) -> bool:
	var channel := ctx.channel
	if channel == null or channel.station < 0 or channel.effect.is_endless():
		return false
	var age := MovementRule.claim_age(ctx.state, ctx.actor, ctx.tick)
	if age < 0 or age > STALE_TICKS:
		return true
	return MovementRule.credit_gain(ctx.state, ctx.actor, ctx.tick) > STALE_TICKS
