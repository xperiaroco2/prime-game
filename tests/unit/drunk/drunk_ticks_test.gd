extends GdUnitTestSuite
## DrunkTicks and the sobering (#1390; ARCHITECTURE §9.4.5, §7.1): a drink at tick t loses its
## first point at t + step exactly (step: PlayerRules.drunk_point_s in ticks) and is gone after
## AMOUNT steps, the stamp then -1; a second drink adds and keeps the stamp; two drinkers decay
## apart; each change reaches the drinker's SelfStatus. A placement, a knockdown, a respawn and a
## reset sober a player up, so nobody drunk reaches a round. Driven by FixtureBar.

const P1 := FixtureBar.P1
const P2 := FixtureBar.P2


func test_a_drink_falls_one_point_per_step_exactly() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	var step := DrunkTicks.step_of(game.state.player_rules)
	FixtureBar.pour(game, P1, 1)
	FixtureBar.drink(game, P1, 2)
	# A command is applied at the next tick (FixtureModes.send).
	var drank := game.ticked_through() + 1
	var player := game.state.player(P1)
	assert_int(player.drunk_stamp).is_equal(drank + step)
	_run_to(game, drank + step - 1)
	assert_int(player.drunk).is_equal(FixtureBar.AMOUNT)
	_run_to(game, drank + step)
	assert_int(player.drunk).is_equal(FixtureBar.AMOUNT - 1)
	_run_to(game, drank + FixtureBar.AMOUNT * step - 1)
	assert_int(player.drunk).is_equal(1)
	_run_to(game, drank + FixtureBar.AMOUNT * step)
	assert_int(player.drunk).is_equal(0)
	assert_int(player.drunk_stamp).is_equal(-1)
	FixtureModes.run_ticks(game, step * 2)
	assert_int(player.drunk).is_equal(0)
	var own := game.view_of(P1).events_named(&"SelfStatus")
	assert_int((own[own.size() - 1] as SelfStatusEvent).drunk).is_equal(0)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_second_drink_adds_and_keeps_the_stamp_and_drinkers_decay_apart() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	var step := DrunkTicks.step_of(game.state.player_rules)
	FixtureBar.pour(game, P1, 1)
	FixtureBar.drink(game, P1, 2)
	var stamp := game.state.player(P1).drunk_stamp
	FixtureModes.run_ticks(game, 3)
	FixtureBar.pour(game, P1, 3)
	FixtureBar.drink(game, P1, 4)
	FixtureBar.pour(game, P2, 5)
	FixtureBar.drink(game, P2, 6)
	assert_int(game.state.player(P1).drunk).is_equal(2 * FixtureBar.AMOUNT)
	assert_int(game.state.player(P1).drunk_stamp).is_equal(stamp)
	_run_to(game, stamp)
	assert_int(game.state.player(P1).drunk).is_equal(2 * FixtureBar.AMOUNT - 1)
	assert_int(game.state.player(P2).drunk).is_equal(FixtureBar.AMOUNT)
	assert_int(game.state.player(P2).drunk_stamp).is_greater(stamp)
	assert_int(step).is_greater(3)


func test_a_knockdown_sobers_up() -> void:
	var game := _drunk_pair()
	for peer: int in [P1, P2]:
		LifeRules.knock_down(_ctx(game), peer)
	_assert_sober(game)
	FixtureModes.run_ticks(game, 1)
	_assert_told_sober(game)


func test_a_respawn_sobers_up() -> void:
	var game := _drunk_pair()
	for peer: int in [P1, P2]:
		var player := game.state.player(peer)
		player.life = PlayerState.Life.DEAD
		LifeRules.respawn(_ctx(game), peer, Vector3.ZERO)
	_assert_sober(game)


func test_a_reset_sobers_up() -> void:
	var game := _drunk_pair()
	game.state.reset_match()
	_assert_sober(game)


## The deal's placement (Pregame entry) sobers up: no Round phase runs DrunkTicks.
func test_the_placement_of_the_deal_sobers_up() -> void:
	var game := _drunk_pair()
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	FixtureLobbyHands.through_countdown(game)
	for peer: int in [P1, P2]:
		FixtureBaseMode.load_ack(game, peer)
	FixtureBaseMode.through_pregame(game)
	assert_str(game.phase_id()).is_equal("round")
	_assert_sober(game)
	# The drinker's own client is told too (SelfStatus), so its sway (#1391) stops in the round.
	_assert_told_sober(game)


## P1 and P2 at the bar, each a mug down and told so in its own SelfStatus.
func _drunk_pair() -> Match:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	for peer: int in [P1, P2]:
		FixtureBar.pour(game, peer, 10 * peer + 1)
		FixtureBar.drink(game, peer, 10 * peer + 2)
		assert_int(game.state.player(peer).drunk).is_equal(FixtureBar.AMOUNT)
	FixtureModes.run_ticks(game, 1)
	for peer: int in [P1, P2]:
		assert_int(_last_told(game, peer)).is_equal(FixtureBar.AMOUNT)
	return game


## Each drinker's last SelfStatus says drunk 0.
func _assert_told_sober(game: Match) -> void:
	for peer: int in [P1, P2]:
		assert_int(_last_told(game, peer)).is_equal(0)


## The drunk value of `peer`'s last SelfStatus, or -1 without one.
func _last_told(game: Match, peer: int) -> int:
	var told := FixtureMoves.statuses(game, peer)
	return told[told.size() - 1].drunk if not told.is_empty() else -1


func _assert_sober(game: Match) -> void:
	for peer: int in [P1, P2]:
		assert_int(game.state.player(peer).drunk).is_equal(0)
		assert_int(game.state.player(peer).drunk_stamp).is_equal(-1)


func _run_to(game: Match, tick: int) -> void:
	while game.ticked_through() < tick:
		FixtureModes.run_ticks(game, 1)


## A context of `game`'s next tick, as a rule's.
func _ctx(game: Match) -> MatchContext:
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = game.ticked_through() + 1
	return ctx
