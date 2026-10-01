class_name LifeTicks
extends TickSystem
## The tick system of the life states (ARCHITECTURE §3.3, §3.4, §9.4): every tick of the phase
## that lists it, each player whose life state has run out (PlayerState.life_deadline reached)
## moves on, in peer-id order:
## - a downed player whose knockdown time is over dies (LifeRules.die);
## - a dead player whose respawn time is over respawns through `respawn` (a Respawn, run with the
##   dead player as its actor). Without one the dead stay dead until they leave or the match ends.
## M4-4 adds the raise's pause.
##
## A mode whose rules can knock a player down lists it in the phase where they can (the base
## mode's Round); without it the downed would stay downed until they leave, and the mode check
## refuses such a phase (§9.1).
##
## Emits: a death's Died (everyone), then the dropped item's ItemPlaced (everyone) and the facts
## player_died and item_rested; a respawn's events (Respawn.emits()). Demands: the respawn's.

## The respawn of the dead (`respawn` markers in the base mode), or null: the dead stay dead.
@export var respawn: Respawn


func run(ctx: MatchContext) -> void:
	for peer: int in ctx.state.peers():
		var player := ctx.state.players[peer]
		if player.life_deadline < 0 or ctx.tick < player.life_deadline:
			continue
		if player.life == PlayerState.Life.DOWNED:
			LifeRules.die(ctx, peer)
		elif player.life == PlayerState.Life.DEAD:
			player.life_deadline = -1
			if respawn != null:
				var own := ctx.copy()
				own.actor = peer
				respawn.run(own)
		else:
			ctx.error("LifeTicks: player %d has a deadline in life state %d" % [peer, player.life])
			player.life_deadline = -1


func emits() -> Array[Script]:
	var found: Array[Script] = [DiedEvent, ItemPlacedEvent]
	if respawn != null:
		found.append_array(respawn.emits())
	return found


func add_demands(settings: Dictionary[StringName, int], players: int, into: Demands) -> void:
	if respawn != null:
		respawn.add_demands(settings, players, into)
