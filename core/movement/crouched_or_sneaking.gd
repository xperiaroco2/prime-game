class_name CrouchedOrSneaking
extends Condition
## Passes when the actor's last accepted claim crouched or sneaked (PlayerState.crouched, sneaking;
## ARCHITECTURE §9.4; #1485). The base mode holds it negated on the WheelPose rule: a crouched or
## sneaking body takes no wheel pose (`not_allowed`), as a crouched or sneaking claim ends one
## (MovementRule). Rejects with `not_crouched`: the sender knows its own stance, and so does
## everyone (the avatar's `crouched` and `sneaking`).

const NOT_CROUCHED := &"not_crouched"


func _test(ctx: MatchContext) -> bool:
	var actor := ctx.actor_state()
	return actor != null and (actor.crouched or actor.sneaking)


func _reason() -> StringName:
	return NOT_CROUCHED
