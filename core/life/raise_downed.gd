class_name RaiseDowned
extends ChannelEffect
## The raise (ARCHITECTURE §3.4, §7.1, §9.4; vision revision 1, Revive): a living player holds E
## over a downed one for `seconds` (3 in the base mode), a channel (ChannelEffect) whose rule's
## conditions are checked at the start and every tick (the base mode's: TargetDowned, ChannelFree,
## TargetInReach, TargetInSight). While it runs the downed player's knockdown is paused
## (PlayerState.knockdown_left holds what was left, and LifeTicks sees no deadline) and the
## movement rule holds that player in place (holds_target; the engineer's answer 8 on PR #133).
##
## - started(): the knockdown pauses; RaiseStarted (everyone).
## - stopped(): the knockdown runs on from where it paused; RaiseStopped (everyone), which names no
##   cause (answer 7). A stop: a condition failing (the raiser out of reach or out of sight), the
##   raiser's StopRaise or any other applied action of the raiser (§9.2), the raiser hit or downed,
##   the downed player giving up (Die), either player leaving, the phase ending (Channels.stop_all).
## - completed(): LifeRules.revive with `revive_health`: Revived (everyone), and the revived
##   player's SelfStatus at the end of the tick. No RaiseStopped: Revived ends the raise.
##
## Emits: RaiseStarted, RaiseStopped, Revived (everyone); SelfStatus (the revived player).

## Whole points the revived player stands up with, 1 to PlayerRules.health. The neutral default
## is out of bounds on purpose: the data sets it (the base mode: 50, E27).
@export var revive_health := 0


func holds_target() -> bool:
	return true


func started(ctx: MatchContext, channel: Channel) -> void:
	var downed := ctx.state.player(channel.target)
	if downed == null or downed.life != PlayerState.Life.DOWNED:
		ctx.error("RaiseDowned: player %d is not downed" % channel.target)
	else:
		channel.held_at = downed.position
		if downed.life_deadline >= 0:
			downed.knockdown_left = maxi(0, downed.life_deadline - ctx.tick)
			downed.life_deadline = -1
	ctx.emit(RaiseStartedEvent.new(channel.actor, channel.target))


func stopped(ctx: MatchContext, channel: Channel) -> void:
	var downed := ctx.state.player(channel.target)
	if downed != null and downed.life == PlayerState.Life.DOWNED and downed.knockdown_left >= 0:
		downed.life_deadline = ctx.tick + downed.knockdown_left
	if downed != null:
		downed.knockdown_left = -1
	ctx.emit(RaiseStoppedEvent.new(channel.actor, channel.target))


func completed(ctx: MatchContext, channel: Channel) -> void:
	LifeRules.revive(ctx, channel.target, revive_health)


func emits() -> Array[Script]:
	return [RaiseStartedEvent, RaiseStoppedEvent, RevivedEvent, SelfStatusEvent]


func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	var most := mode.player_rules.health if mode.player_rules != null else 1000
	append_found(found, [out_of_bounds("RaiseDowned revive_health", revive_health, 1, most)])
	return found
