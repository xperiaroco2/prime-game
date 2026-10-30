class_name EndLimps
extends RuleEffect
## Everyone limp stands up (#1393; ARCHITECTURE §7.1.21, §9.4.3): a transition action on a row
## from a phase that lists LimpTicks into one that does not (the base mode's Countdown -> Loading),
## so no limp, and no host body, outlasts the level it lies on. Each limp player, in peer order,
## gets up as at its time (LifeRules.get_up: a hit's limp at full health). Then, with
## `restore_health`, every living player below full health is back at full (#1439: the hall's hits
## end with the countdown). Nobody limp and nobody hurt: nothing happens.
##
## Emits: StopBody (server), Correction (the player). No demands.

## Whether every living player is back at full health after the get-ups (LifeRules.restore_health,
## its SelfStatus touched): the base mode's Countdown -> Loading row sets it.
@export var restore_health := false


func run(ctx: MatchContext) -> void:
	for peer: int in ctx.state.peers():
		LifeRules.get_up(ctx, peer)
	if restore_health:
		for peer: int in ctx.state.peers():
			LifeRules.restore_health(ctx, peer)


func emits() -> Array[Script]:
	return [StopBodyEvent, CorrectionEvent]
