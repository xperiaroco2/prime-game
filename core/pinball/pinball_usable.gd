class_name PinballUsable
extends Condition
## Passes when the pinball's seat is free or the actor's own (Pinball.seated; ARCHITECTURE §9.4;
## #1398): the machine's Interact rule holds it after AtStation and StationInSight, so a second
## player cannot take the seat while one plays. Rejects with `unavailable`: who sits is public
## (PinballState).

const UNAVAILABLE := &"unavailable"


func _test(ctx: MatchContext) -> bool:
	var seated := Pinball.seated(ctx.state)
	return seated < 0 or seated == ctx.actor


func _reason() -> StringName:
	return UNAVAILABLE
