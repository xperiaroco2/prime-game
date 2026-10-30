class_name DrunkTicks
extends TickSystem
## The sobering up (#1390; GDD §3 Base mode, "The bar"; ARCHITECTURE §9.4.5): every tick of the
## phase that lists it (the base mode's Lobby and Countdown), each drunk player, in ascending peer
## order, loses one point of PlayerState.drunk at each host tick its `drunk_stamp` has reached, the
## stamp moving on by one PlayerRules.drunk_point_s (Ticks, at least one tick) per point: a player
## who drank `a` points at tick t, and nothing more, is sober at t + a * step exactly. At 0
## the stamp is -1. Each change touches the player's SelfStatus (SelfStatusFeed).
## A drunk player with no stamp (put drunk into MatchState without Drink)
## is a rule error, logged once: its clock starts then.
## A phase that does not list it lowers nothing; placement, knockdown, respawn and reset sober a
## player up anyway (PlayerState.sober).
##
## Emits nothing (the value rides the snapshot and SelfStatus). No demands.


func run(ctx: MatchContext) -> void:
	var rules := ctx.state.player_rules
	if rules == null:
		return
	var step := step_of(rules)
	var peers: Array[int] = []
	peers.assign(ctx.state.players.keys())
	peers.sort()
	for peer: int in peers:
		var player := ctx.state.players[peer]
		if player.drunk <= 0:
			continue
		if player.drunk_stamp < 0:
			ctx.error("DrunkTicks: player %d is drunk with no stamp" % peer)
			player.drunk_stamp = ctx.tick + step
			continue
		var was := player.drunk
		while player.drunk > 0 and ctx.tick >= player.drunk_stamp:
			player.drunk -= 1
			player.drunk_stamp += step
		if player.drunk == 0:
			player.drunk_stamp = -1
		if player.drunk != was:
			SelfStatusFeed.touch(ctx.state, peer)


## The ticks one drunk point lasts under `rules`: PlayerRules.drunk_point_s, at least one tick.
static func step_of(rules: PlayerRules) -> int:
	return maxi(1, Ticks.from_seconds(rules.drunk_point_s))
