class_name TargetInSight
extends Condition
## Passes when the line from the actor's eye (Items.eye_of: the floor it stands on, raised by
## PlayerRules.eye_height_m) to just above the rule's target player's feet (Items.lifted: where a
## downed player lies) is clear of walls (WorldQuery.line_of_sight; ARCHITECTURE §7.1, §9.4; M4-4),
## as InSight is for an item. Checked at the start and every tick: losing sight stops a raise like
## moving out of reach (the engineer's answer 4 on PR #133). Rejects with `blocked`: the sender sees
## the wall too.

const BLOCKED := &"blocked"


## It needs a target player (Channels.target_of), and also reads the actor (the default).
func needs_target() -> bool:
	return true


func _test(ctx: MatchContext) -> bool:
	var actor := ctx.actor_state()
	var target := ctx.state.player(Channels.target_of(ctx))
	if actor == null or target == null or ctx.state.player_rules == null:
		return false
	return ctx.world.line_of_sight(Items.eye_of(ctx, actor), Items.lifted(target.position))


func _reason() -> StringName:
	return BLOCKED
