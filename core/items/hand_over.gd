class_name HandOver
extends RuleEffect
## The actor's hand item goes to the rule's target player (the intent's `target`; ARCHITECTURE
## §7.1, §9.4; GDD §6 "The hand and the belt", #1389): Items.hand_over. The item leaves the
## giver's place (its selection stays: an empty hand) and arrives as a give does: into the
## receiver's hand, or onto its belt beside a hand item, a full receiver's hand item put down at
## its feet first. Run it after the conditions required_conditions() lists. As every applied
## action does, it stops the actor's running channel first (RuleRunner).
##
## Emits: ItemPickedUp (everyone, its `peer` the receiver: the clients move the item from the
## giver's hand by it); for a full receiver first ItemPlaced (put_down, everyone) and item_rested
## for the item it puts down.


func run(ctx: MatchContext) -> void:
	Items.hand_over(ctx, ctx.actor, Channels.target_of(ctx), Items.held_by(ctx.state, ctx.actor))


## The condition classes a rule holding this effect must hold, not negated (ModeCheck): the item
## (HoldsItem, HandNotTwoHanded, HandHandable), the receiver (TargetLiving) and the geometry
## (TargetInReach, TargetInSight), so no mode hands over a belt item, a two-handed one or one to
## a player far away or behind a wall.
static func required_conditions() -> Array[Script]:
	return [HoldsItem, HandNotTwoHanded, HandHandable, TargetLiving, TargetInReach, TargetInSight]


func emits() -> Array[Script]:
	return [ItemPickedUpEvent, ItemPlacedEvent]
