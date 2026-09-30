class_name FixtureTire
extends RuleEffect
## Spends `amount` whole points of player `peer`'s stamina and touches its SelfStatus: a part that
## changes a player's status outside a command, for example as a transition's action.

@export var peer := 1
@export var amount := 1


static func of(of_peer: int, points: int) -> FixtureTire:
	var effect := FixtureTire.new()
	effect.peer = of_peer
	effect.amount = points
	return effect


func run(ctx: MatchContext) -> void:
	var player := ctx.state.player(peer)
	if player == null:
		return
	StaminaLedger.spend(player, Ticks.thousandths(amount))
	SelfStatusFeed.touch(ctx.state, peer)
