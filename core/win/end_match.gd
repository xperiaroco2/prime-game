class_name EndMatch
extends RuleEffect
## Ends the match (ARCHITECTURE §3.2, §9.2, §9.4): a transition action of `Round, won -> End`. It
## records the side of the `won` outcome, the outcome's argument, as MatchState.winner and emits
## MatchEnded with that side and, when a win condition reported the `won`, its id as the reason
## with the round's play time (`time`, whole seconds the clock ran; none when it never started),
## #548. No names, no roles (§5: the reason and the time are public). The clock stops because
## End's clock does not run. An argument that is no side of the mode is a rule error: logged, and
## nothing is recorded or emitted.
##
## Emits: MatchEnded (everyone). No demands.

## The reason's argument: the round's play time in whole seconds.
const TIME := &"time"


func run(ctx: MatchContext) -> void:
	var argument: Variant = ctx.outcome_argument
	if not (argument is StringName or argument is String):
		ctx.error("EndMatch: the outcome %s carries no side" % ctx.outcome)
		return
	var side := StringName(str(argument))
	if ctx.mode.find_side(side) == null:
		ctx.error("EndMatch: %s is not a side of the mode" % side)
		return
	ctx.state.winner = side
	var numbers: Dictionary[StringName, int] = {}
	if not ctx.outcome_reason.is_empty() and ctx.state.clock_ticks_total > 0:
		var ran := ctx.state.clock_ticks_total - maxi(ctx.state.clock_ticks_left, 0)
		numbers[TIME] = floori(ran / float(Ticks.RATE))
	ctx.emit(MatchEndedEvent.new(side, ctx.outcome_reason, numbers))


func emits() -> Array[Script]:
	return [MatchEndedEvent]
