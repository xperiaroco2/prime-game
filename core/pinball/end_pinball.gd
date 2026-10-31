class_name EndPinball
extends RuleEffect
## The pinball's running game ends (Pinball.end; ARCHITECTURE §7.1.22, §9.4; #1398): a transition
## action on a row from a phase that lists PinballTicks into one that does not (the base mode's
## Countdown -> Loading), so no seat survives into a match (PinballTicks.problems). The score
## counts for the best. None running: nothing happens.
##
## Emits: PinballState (everyone). No demands.


func run(ctx: MatchContext) -> void:
	Pinball.end(ctx)


func emits() -> Array[Script]:
	return [PinballStateEvent]
