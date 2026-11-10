class_name LifeTicks
extends TickSystem
## The tick system of the life states (ARCHITECTURE §3.3, §3.4, §9.4): every tick of the phase
## that lists it, each player whose life state has run out (PlayerState.life_deadline reached)
## moves on, in peer-id order:
## - a downed player whose knockdown time is over dies (LifeRules.die);
## - a dead player whose respawn time is over respawns through `respawn` (a Respawn, run with the
##   dead player as its actor). Without one the dead stay dead until they leave or the match ends;
## - a printing player (#1489) whose print is over stands living (LifeRules.finish_print).
## A dead player not yet in the hall of a phase with one is sent there (Respawn.send_to_hall).
## Before its deadline, each player's body motion counts a tick (LifeRules.count_motion, the
## knockdown rework's KE3, KE15): one that has lasted the longest motion rests (StopBody).
## A downed player being raised has no deadline: the raise (RaiseDowned, M4-4) keeps what was left
## of its knockdown in PlayerState.knockdown_left and sets it again when it stops.
##
## A mode whose rules can knock a player down lists it in the phase where they can (the base
## mode's Round); without it the downed would stay downed until they leave, and the mode check
## refuses such a phase (§9.1).
##
## Emits: a motion's end StopBody (server: the longest motion, LifeRules.count_motion); a death's
## StopBody when its body moved, Died (everyone), then the dropped item's ItemPlaced (everyone)
## and the facts player_died and item_rested; a respawn's events (Respawn.emits()); the end of a
## print's Respawned (everyone). Demands: the respawn's.

## The respawn of the dead (`respawn` markers in the base mode), or null: the dead stay dead.
@export var respawn: Respawn


func run(ctx: MatchContext) -> void:
	for peer: int in ctx.state.peers():
		var player := ctx.state.players[peer]
		LifeRules.count_motion(ctx, peer)
		if player.life_deadline >= 0 and ctx.tick >= player.life_deadline:
			_expire(ctx, player)
		if respawn != null and player.life == PlayerState.Life.DEAD and not player.in_hall:
			var own := ctx.copy()
			own.actor = peer
			respawn.send_to_hall(own)


## `player`'s life state has run out at this tick (run()).
func _expire(ctx: MatchContext, player: PlayerState) -> void:
	if player.life == PlayerState.Life.DOWNED:
		LifeRules.die(ctx, player.peer)
	elif player.life == PlayerState.Life.DEAD:
		player.life_deadline = -1
		if respawn != null:
			var own := ctx.copy()
			own.actor = player.peer
			respawn.run(own)
	elif player.is_printing():
		LifeRules.finish_print(ctx, player.peer)
	else:
		ctx.error(
			"LifeTicks: player %d has a deadline in life state %d" % [player.peer, player.life]
		)
		player.life_deadline = -1


func emits() -> Array[Script]:
	var found: Array[Script] = [DiedEvent, ItemPlacedEvent, StopBodyEvent]
	if respawn != null:
		found.append_array(respawn.emits())
	return found


func add_demands(settings: Dictionary[StringName, int], players: int, into: Demands) -> void:
	if respawn != null:
		respawn.add_demands(settings, players, into)
