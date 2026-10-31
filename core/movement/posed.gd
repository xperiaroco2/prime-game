class_name Posed
extends Condition
## Passes when the actor sits in the chair's seated pose (PlayerState.posed; ARCHITECTURE §9.4;
## #1485). The base mode holds it negated on the WheelPose rule: the chair and the pose wheel
## exclude each other, so a seated player takes no wheel pose (`not_allowed`). Rejects with
## `not_posed`: the sender knows whether it sits, and so does everyone (the avatar's `posed`).

const NOT_POSED := &"not_posed"


func _test(ctx: MatchContext) -> bool:
	var actor := ctx.actor_state()
	return actor != null and actor.posed


func _reason() -> StringName:
	return NOT_POSED
