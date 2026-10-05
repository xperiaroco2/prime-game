class_name TargetDowned
extends Condition
## Passes when the rule's target player (Channels.target_of: the intent's `target`, or the
## channel's) is downed (ARCHITECTURE §9.4; M4-4): the raise's first condition, checked at the
## start and every tick. Rejects with `not_downed`: whether a player is downed is public
## (KnockedDown, the snapshot's flag).

const NOT_DOWNED := &"not_downed"


## It reads the rule's target player, not the actor.
func reads_actor_state() -> bool:
	return false


## It needs a target player, which only an intent or a channel gives: no fact carries one.
func needs_target() -> bool:
	return true


func _test(ctx: MatchContext) -> bool:
	var target := ctx.state.player(Channels.target_of(ctx))
	return target != null and target.life == PlayerState.Life.DOWNED


func _reason() -> StringName:
	return NOT_DOWNED
