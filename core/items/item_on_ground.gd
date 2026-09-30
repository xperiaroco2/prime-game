class_name ItemOnGround
extends Condition
## Passes when the rule's item (the intent's `item`, Items.target_of) exists, lies on the ground
## and is interactive: not held, and not locked as a delivered package is (ARCHITECTURE §9.4).
## Rejects with `unavailable`, which reveals nothing hidden: whether an item is held or delivered
## is public.

const UNAVAILABLE := &"unavailable"


func _test(ctx: MatchContext) -> bool:
	var item := Items.target_of(ctx)
	return item != null and item.where == ItemState.Where.GROUND


func _reason() -> StringName:
	return UNAVAILABLE
