class_name HandHandable
extends Condition
## Passes unless the actor holds an item whose kind is not handable (ItemKind.handable) in the hand
## (ARCHITECTURE §9.4; #1389): the base mode's HandOver, so only a kind the data marks may be
## handed to another player. An empty hand passes (HoldsItem comes first, as for
## HandNotTwoHanded). Rejects with `not_handable`: the sender knows what it holds, and so does
## everyone (the avatar's hand item).

const NOT_HANDABLE := &"not_handable"


func _test(ctx: MatchContext) -> bool:
	var hand := Items.held_by(ctx.state, ctx.actor)
	return hand == null or hand.kind.is_handable()


func _reason() -> StringName:
	return NOT_HANDABLE
