class_name EndMatch
extends RuleEffect
## Ends the match (ARCHITECTURE §3.2, §9.2, §9.4): a transition action of `Round, won -> End`. It
## records the side of the `won` outcome, the outcome's argument, as MatchState.winner and emits
## MatchEnded with that side and, when a win condition reported the `won`, its id as the reason
## with the round's play time (`time`, whole seconds the clock ran; none when it never started),
## #548. No names, no roles (§5: the reason and the time are public). The clock stops because
## End's clock does not run. An empty side from a win condition (WinCondition.side empty,
## #1627) ends the match with no side winning: MatchState.winner stays empty and MatchEnded names
## the empty side with the condition's reason. Any other argument that is no side of the mode
## (an empty one with no win condition behind it among them) is a rule error: logged, and nothing
## is recorded or emitted.
## The dead leave the dead's hall here (#1489): at End they are the dead of today's end.
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
	var no_winner := side.is_empty() and not ctx.outcome_reason.is_empty()
	if not no_winner and ctx.mode.find_side(side) == null:
		ctx.error("EndMatch: %s is not a side of the mode" % side)
		return
	ctx.state.winner = side
	# The end is the same for all (#1489): the hall ends with the Round, no player waits in it at End.
	for peer: int in ctx.state.peers():
		ctx.state.players[peer].leave_hall()
	var numbers: Dictionary[StringName, int] = {}
	if not ctx.outcome_reason.is_empty() and ctx.state.clock_ticks_total > 0:
		var ran := ctx.state.clock_ticks_total - maxi(ctx.state.clock_ticks_left, 0)
		numbers[TIME] = floori(ran / float(Ticks.RATE))
	ctx.emit(MatchEndedEvent.new(side, ctx.outcome_reason, numbers))


func emits() -> Array[Script]:
	return [MatchEndedEvent]
