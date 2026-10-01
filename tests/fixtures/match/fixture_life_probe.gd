class_name FixtureLifeProbe
extends RuleEffect
## A transition action that records which players are downed when it runs: a probe of the order
## of a row's actions (ResetMatch before PlacePlayers).

var downed_seen: Array[int] = []


func run(ctx: MatchContext) -> void:
	for peer: int in ctx.state.present_peers():
		if ctx.state.players[peer].life == PlayerState.Life.DOWNED:
			downed_seen.append(peer)
