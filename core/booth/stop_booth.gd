class_name StopBooth
extends RuleEffect
## Ends a running photo booth session with no print (#1396; ARCHITECTURE §9.4.2, §9.5.28): a
## transition action of every row that leaves a phase listing BoothTicks for one that does not (the
## base mode's `Lobby, all_ready -> Countdown`), so a session never outlives its clock; the frames
## taken so far print nothing (provisional, #1396). Nothing when no session runs.
##
## Emits: BoothStep (STOPPED; everyone), only when a session ran. No demands.


func run(ctx: MatchContext) -> void:
	BoothSessions.stop(ctx)


func emits() -> Array[Script]:
	return [BoothStepEvent]
