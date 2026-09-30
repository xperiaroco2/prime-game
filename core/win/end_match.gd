class_name EndMatch
extends RuleEffect
## Ends the match (ARCHITECTURE §3.2, §9.2, §9.4): a transition action of `Round, won -> End`. It
## records the side of the `won` outcome, the outcome's argument, as MatchState.winner and emits
## MatchEnded with that side and nothing else: no names, no roles (§5, End widens nothing). The
## clock stops because End's clock does not run. An argument that is no side of the mode is a
## rule error: logged, and nothing is recorded or emitted.
##
## Emits: MatchEnded (everyone). No demands.


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
	ctx.emit(MatchEndedEvent.new(side))


func emits() -> Array[Script]:
	return [MatchEndedEvent]
