class_name ClearStations
extends RuleEffect
## Removes every station of the match (#1390; ARCHITECTURE §3.2, §9.4.2): a transition action of
## `Countdown, countdown_done -> Loading` beside ClearItems, so the lobby's tap (StationTicks) never
## reaches Pregame or Round, where an Interact at its old spot would pour a mug on the map. The next
## station placed is numbered 1 again (MatchState.clear_stations), so the deal's stations number
## from 1 as in a lobby without one. Run before the deal only: a dealt task names its stations.
##
## Emits nothing: every client forgets its stations at LoadMatch (ClientModel.clear_match), which
## the same transition sends. No demands.


func run(ctx: MatchContext) -> void:
	if not ctx.state.tasks.is_empty():
		ctx.error("ClearStations: tasks are dealt; their stations stay")
		return
	ctx.state.clear_stations()
