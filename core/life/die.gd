class_name Die
extends RuleEffect
## The actor, downed, dies at once (ARCHITECTURE §3.4, §9.4; vision revision 1, Give up): the
## effect of the base mode's GiveUp, which Round accepts from the downed only. LifeRules.die first
## stops every channel the player is the target of (a raise of it: RaiseStopped), then its body,
## Died, player_died and the drop at the body, as when a knockdown runs out. A living actor is a
## rule error, logged, and nothing happens.
##
## Emits: RaiseStopped (everyone), when it was being raised; Died (everyone); the dropped item's
## ItemPlaced (death, everyone). Raises player_died, then item_rested.


func run(ctx: MatchContext) -> void:
	LifeRules.die(ctx, ctx.actor)


func emits() -> Array[Script]:
	return [RaiseStoppedEvent, DiedEvent, ItemPlacedEvent]
