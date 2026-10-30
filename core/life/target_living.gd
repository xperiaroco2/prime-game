class_name TargetLiving
extends Condition
## Passes when the rule's target player (Channels.target_of: the intent's `target`) is another
## player, present, alive and standing: not the actor itself, not limp, downed, dead or gone
## (ARCHITECTURE §9.4; #1389, #1434): the hand-over offer's receiver, the take's giver. Rejects with
## `not_living` (a player's life state is public: KnockedDown, Died, the snapshot's `limp`; so is
## who is present), and with `bad_args` when the target is the actor itself (the sender knows its
## own id).

const NOT_LIVING := &"not_living"


## It needs a target player, which only an intent or a channel gives: no fact carries one. It
## also reads the actor (the default), whom the target must not be.
func needs_target() -> bool:
	return true


func rejection_reason_in(ctx: MatchContext) -> StringName:
	if not negate and Channels.target_of(ctx) == ctx.actor:
		return RejectReasons.BAD_ARGS
	return rejection_reason()


func _test(ctx: MatchContext) -> bool:
	var peer := Channels.target_of(ctx)
	if peer == ctx.actor:
		return false
	var target := ctx.state.player(peer)
	return target != null and target.life == PlayerState.Life.ALIVE and not target.is_limp()


func _reason() -> StringName:
	return NOT_LIVING
