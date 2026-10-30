class_name EndLimps
extends RuleEffect
## Everyone limp stands up (#1393; ARCHITECTURE §7.1.21, §9.4.3): a transition action on a row
## from a phase that lists LimpTicks into one that does not (the base mode's Countdown -> Loading),
## so no limp, and no host body, outlasts the level it lies on. Each limp player, in peer order,
## gets up as at its time (LifeRules.get_up). Nobody limp: nothing happens.
##
## Emits: StopBody (server), Correction (the player). No demands.


func run(ctx: MatchContext) -> void:
	for peer: int in ctx.state.peers():
		LifeRules.get_up(ctx, peer)


func emits() -> Array[Script]:
	return [StopBodyEvent, CorrectionEvent]
