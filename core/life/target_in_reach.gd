class_name TargetInReach
extends Condition
## Passes when the rule's target player (Channels.target_of) lies within `reach_m` of the actor:
## both last accepted positions, their feet, never a position inside the intent (ARCHITECTURE
## §7.1, §9.4; M4-4). The raise's reach is the pick-up's (2 m in the base mode). Checked at the
## start and every tick: a raiser who walks away stops the raise. Rejects with `out_of_reach`: the
## sender knows both positions.

const OUT_OF_REACH := &"out_of_reach"

## Metres, 0.1 to 10. The neutral default is out of bounds on purpose: the data sets it (the base
## mode's raise: 2), so the mode check refuses a rule that forgot it.
@export var reach_m := 0.0


func _test(ctx: MatchContext) -> bool:
	var actor := ctx.actor_state()
	var target := ctx.state.player(Channels.target_of(ctx))
	if actor == null or target == null:
		return false
	return actor.position.distance_to(target.position) <= reach_m


func _reason() -> StringName:
	return OUT_OF_REACH


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(found, [out_of_bounds("TargetInReach reach_m", reach_m, 0.1, 10)])
	return found
