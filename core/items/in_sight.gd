class_name InSight
extends Condition
## Passes when the line from the actor's eye to the rule's item (Items.target_of) is clear of
## walls (WorldQuery.line_of_sight; ARCHITECTURE §7.1, §9.4). The eye is the actor's last
## accepted position raised by the mode's PlayerRules.eye_height_m. The line ends just above the
## item's rest position (Items.lifted), so the floor or crate it lies on does not block it.
## Rejects with `blocked`: the sender sees the wall too.

const BLOCKED := &"blocked"


func _test(ctx: MatchContext) -> bool:
	var actor := ctx.actor_state()
	var item := Items.target_of(ctx)
	if actor == null or item == null or ctx.state.player_rules == null:
		return false
	var eye := actor.position + Vector3.UP * ctx.state.player_rules.eye_height_m
	return ctx.world.line_of_sight(eye, Items.lifted(item.position))


func _reason() -> StringName:
	return BLOCKED
