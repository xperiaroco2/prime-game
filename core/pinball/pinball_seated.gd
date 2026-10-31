class_name PinballSeated
extends Condition
## Passes when the actor is the pinball's seated player and still present, alive and standing
## (Pinball.seated, Pinball.standing; ARCHITECTURE §9.4; #1398): the Flippers rule holds it, so
## only the seated player's flippers count. Flippers is no player's action (Intents.PLAYER_ACTIONS),
## so Match._accepts lets a limp sender through: this refuses it, before PinballTicks frees the
## seat. Rejects with `not_seated`: who sits is public (PinballState).


func _test(ctx: MatchContext) -> bool:
	return Pinball.seated(ctx.state) == ctx.actor and Pinball.standing(ctx.actor_state())


func _reason() -> StringName:
	return Pinball.NOT_SEATED
