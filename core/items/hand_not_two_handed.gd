class_name HandNotTwoHanded
extends Condition
## Passes unless the actor holds a two-handed item (ItemKind.hands 2) in the hand (ARCHITECTURE
## §9.4; vision revision 1, V13): the base mode's Swap, so a package carrier cannot draw a belted
## knife. An empty hand passes. Rejects with `two_handed`: the sender knows what it holds, and so
## does everyone (the avatar's hand item).

const TWO_HANDED := &"two_handed"


func _test(ctx: MatchContext) -> bool:
	var hand := Items.held_by(ctx.state, ctx.actor)
	return hand == null or not hand.kind.is_two_handed()


func _reason() -> StringName:
	return TWO_HANDED
