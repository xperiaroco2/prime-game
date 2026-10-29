class_name DrawPlace
extends RuleEffect
## The intent's `place` comes into the actor's hand (ARCHITECTURE §7.1, §9.4; GDD §6 "Drawing from
## the belt": keys 1, 2, 3 and the wheel): Items.select. The hand item stays in its place, on the
## belt; a two-handed one is put down at the feet first (no refusal). Run it after PlaceInRange and
## PlaceChanges. Instant; as every applied action does, it stops the actor's running channel first
## (RuleRunner: a raiser who draws stops its raise).
##
## Emits: ItemPlaced (everyone; a two-handed hand item put down), Swapped (everyone).


func run(ctx: MatchContext) -> void:
	Items.select(ctx, ctx.actor, ctx.command.get_int("place", -1))


func emits() -> Array[Script]:
	return [ItemPlacedEvent, SwappedEvent]
