class_name LifeTicks
extends TickSystem
## The tick system of the life states (ARCHITECTURE §3.3, §3.4, §9.4): every tick of the phase
## that lists it, each player whose life state has run out (PlayerState.life_deadline reached)
## moves on, in peer-id order. Today that is the knockdown: a downed player whose knockdown time
## is over dies (LifeRules.die). M4-3 adds the respawn of the dead, M4-4 the raise's pause.
##
## A mode whose rules can knock a player down lists it in the phase where they can (the base
## mode's Round); without it the downed would stay downed until they leave.
##
## Emits: a death's Died (everyone), then the dropped item's ItemPlaced (everyone) and the facts
## player_died and item_rested.


func run(ctx: MatchContext) -> void:
	for peer: int in ctx.state.peers():
		var player := ctx.state.players[peer]
		if player.life_deadline < 0 or ctx.tick < player.life_deadline:
			continue
		if player.life == PlayerState.Life.DOWNED:
			LifeRules.die(ctx, peer)
		else:
			ctx.error("LifeTicks: player %d has a deadline in life state %d" % [peer, player.life])
			player.life_deadline = -1


func emits() -> Array[Script]:
	return [DiedEvent, ItemPlacedEvent]
