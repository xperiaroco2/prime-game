extends GdUnitTestSuite
## NoneAlive and the dissidents' "no crew present" (ARCHITECTURE §3.4, §3.5, §9.4, §9.5): the
## dissidents win when every crew member has left, and not while one is present, living, downed or
## dead (M4-2: killing takes time from the crew, it does not end the round). Also the order of
## effects inside one command (§3.4), with the real win conditions in the base mode's order: the
## last crew member leaving with the last package over its circle is a dissident win, while a
## dying carrier's package that drops into its circle is a delivery. Driven through seeded
## matches of FixtureWinModes, asserted on the events and on view_of.

const P1 := 1
const P2 := 2
const P3 := 3


func test_a_knocked_down_or_dead_last_crew_member_ends_nothing() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), [P1, P2])
	var dissident := FixtureDealModes.players_of(game, &"dissident")[0]
	var crew := FixtureDealModes.players_of(game, &"crew")[0]
	FixtureItemModes.stand(game, crew, Vector3(40, 0, 40))
	FixtureWinModes.knock_down(game, dissident, crew)
	assert_int(game.state.player(crew).life).is_equal(PlayerState.Life.DOWNED)
	assert_str(game.phase_id()).is_equal("round")
	FixtureWinModes.run_out(game, crew)
	assert_int(game.state.player(crew).life).is_equal(PlayerState.Life.DEAD)
	assert_str(game.phase_id()).is_equal("round")
	for peer: int in [P1, P2]:
		assert_array(FixtureWinModes.ended(game, peer)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_dissidents_win_once_every_crew_member_has_left() -> void:
	# Three players, two crew: one killed is dead, the other leaving still leaves the dead one
	# present; the round ends when the dead one leaves too (§3.5).
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), [P1, P2, P3])
	var dissident := FixtureDealModes.players_of(game, &"dissident")[0]
	var crew := FixtureDealModes.players_of(game, &"crew")
	FixtureItemModes.stand(game, crew[0], Vector3(40, 0, 40))
	FixtureItemModes.stand(game, crew[1], Vector3(-40, 0, 40))
	FixtureWinModes.kill(game, dissident, crew[0])
	assert_int(game.state.player(crew[0]).life).is_equal(PlayerState.Life.DEAD)
	FixtureModes.send(game, Intents.PEER_LEFT, crew[1])
	assert_str(game.phase_id()).is_equal("round")
	FixtureModes.send(game, Intents.PEER_LEFT, crew[0])
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("dissidents")
	assert_array(FixtureWinModes.ended(game, dissident)).is_equal([&"dissidents"])
	# The players who left get nothing more (§5: everyone is every player who has not left).
	for peer: int in crew:
		assert_array(FixtureWinModes.ended(game, peer)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_dead_dissident_ends_nothing() -> void:
	# Killing a dissident gives the crew nothing by itself (MVP rules).
	var mode := FixtureWinModes.basic(2)
	var game := FixtureWinModes.in_round(mode, [P1, P2, P3], {&"dissidents": 2})
	var dissidents := FixtureDealModes.players_of(game, &"dissident")
	assert_int(dissidents.size()).is_equal(2)
	FixtureItemModes.stand(game, dissidents[1], Vector3(40, 0, 40))
	FixtureWinModes.kill(game, dissidents[0], dissidents[1])
	assert_int(game.state.player(dissidents[1]).life).is_equal(PlayerState.Life.DEAD)
	assert_str(game.phase_id()).is_equal("round")


func test_a_dying_carriers_package_that_drops_into_its_circle_is_delivered() -> void:
	# Vision revision 1 (V4): a downed carrier who dies in its circle delivers. Its death is no
	# dissident win any more, and the package drops at the body, inside the circle.
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(1), [P1, P2])
	var dissident := FixtureDealModes.players_of(game, &"dissident")[0]
	var crew := FixtureDealModes.players_of(game, &"crew")[0]
	var package := FixtureWinModes.hold_over_circle(game, crew, 0)
	FixtureWinModes.knock_down(game, dissident, crew)
	assert_int(package.holder).is_equal(crew)
	assert_str(game.phase_id()).is_equal("round")
	FixtureWinModes.run_out(game, crew)
	assert_int(package.where).is_equal(ItemState.Where.LOCKED)
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("crew")
	for peer: int in [P1, P2]:
		assert_array(FixtureWinModes.ended(game, peer)).is_equal([&"crew"])
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_last_crew_member_leaving_with_the_last_package_over_its_circle() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(1), [P1, P2])
	var dissident := FixtureDealModes.players_of(game, &"dissident")[0]
	var crew := FixtureDealModes.players_of(game, &"crew")[0]
	var package := FixtureWinModes.hold_over_circle(game, crew, 0)
	FixtureModes.send(game, Intents.PEER_LEFT, crew)
	_assert_dissidents_won_before_the_delivery(game, package, [dissident])


func test_the_same_package_put_down_in_its_circle_wins_for_the_crew() -> void:
	# The control of the leave above: without the leave the delivery wins.
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(1), [P1, P2])
	var crew := FixtureDealModes.players_of(game, &"crew")[0]
	FixtureWinModes.hold_over_circle(game, crew, 0)
	FixtureItemModes.stand(game, crew, game.state.player(crew).position - Vector3(1, 0, 0))
	FixtureItemModes.put_down(game, crew, Vector3.RIGHT)
	assert_str(game.phase_id()).is_equal("end")
	for peer: int in [P1, P2]:
		assert_array(FixtureWinModes.ended(game, peer)).is_equal([&"crew"])


func test_the_condition_reads_sides_through_roles_and_holds_once_the_side_has_left() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(2), [P1, P2])
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	assert_bool(NoneAlive.of(&"crew").passes(ctx)).is_false()
	assert_bool(NoneAlive.of(&"dissidents").passes(ctx)).is_false()
	# The downed and the dead are present: they still count.
	for life: PlayerState.Life in [PlayerState.Life.DOWNED, PlayerState.Life.DEAD]:
		for peer: int in [P1, P2]:
			game.state.player(peer).life = life
		assert_bool(NoneAlive.of(&"crew").passes(ctx)).is_false()
		assert_bool(NoneAlive.of(&"dissidents").passes(ctx)).is_false()
	for peer: int in [P1, P2]:
		game.state.player(peer).life = PlayerState.Life.LEFT
	assert_bool(NoneAlive.of(&"crew").passes(ctx)).is_true()
	assert_bool(NoneAlive.of(&"dissidents").passes(ctx)).is_true()
	# A player without a role of the mode belongs to no side.
	game.state.player(P1).life = PlayerState.Life.ALIVE
	game.state.player(P1).role = &""
	assert_bool(NoneAlive.of(&"crew").passes(ctx)).is_true()


func test_the_mode_check_refuses_a_side_the_mode_does_not_declare() -> void:
	var mode := FixtureWinModes.basic(2)
	assert_array(Array(NoneAlive.of(&"crew").check(mode))).is_empty()
	assert_array(Array(NoneAlive.of(&"pirates").check(mode))).has_size(1)
	assert_array(Array(NoneAlive.new().check(mode))).is_equal(["NoneAlive has no side"])
	mode.win_conditions[1].conditions = [NoneAlive.of(&"pirates")]
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("NoneAlive names side pirates")


func _assert_dissidents_won_before_the_delivery(
	game: Match, package: ItemState, peers: Array[int]
) -> void:
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("dissidents")
	# The package did land in its circle: the delivery happened, after the win was reported.
	assert_int(package.where).is_equal(ItemState.Where.LOCKED)
	assert_bool(Tasks.all_done(game.state)).is_true()
	for peer: int in peers:
		assert_array(FixtureWinModes.ended(game, peer)).is_equal([&"dissidents"])
		var names := game.view_of(peer).event_names()
		var delivered := names.find(&"PackageDelivered")
		assert_int(delivered).is_greater(-1)
		assert_int(names.find(&"MatchEnded")).is_greater(delivered)
	assert_array(Array(game.diagnostics)).is_empty()
