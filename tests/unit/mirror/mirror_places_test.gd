extends GdUnitTestSuite
## The lobby mirror's places (#1394; ARCHITECTURE §7.1.24, §9.4): one station per `mirror` marker;
## an Interact at a free place takes it and every peer sees the same places (MirrorPlaces); two
## players hold two places at once; a place another player holds refuses `unavailable`; the
## holder's Interact again gives it up, one at another place moves it there; a walk away, a
## knockdown, a death, a limp, a leave and the row out of the lobby's phases (EndMirror) give it up,
## so no place survives into a match; a cancelled countdown keeps it; a joiner is told the places.
## Driven by FixtureMirror.

const P1 := FixtureMirror.P1
const P2 := FixtureMirror.P2
const P3 := FixtureMirror.P3


func test_every_marker_is_a_place_from_the_first_tick() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1])
	assert_int(FixtureMirror.place(game, 0)).is_not_equal(-1)
	assert_int(FixtureMirror.place(game, 1)).is_not_equal(-1)
	assert_int(FixtureMirror.place(game, 0)).is_not_equal(FixtureMirror.place(game, 1))
	assert_int(game.view_of(P1).events_named(&"StationPlaced").size()).is_equal(2)
	FixtureModes.run_ticks(game, 3)
	assert_int(game.state.stations.size()).is_equal(2)


func test_an_interact_takes_a_place_and_every_peer_sees_it() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2, P3])
	assert_array(FixtureMirror.told(game, P1)).is_empty()
	FixtureMirror.use(game, P1, 0)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	var place := FixtureMirror.place(game, 0)
	assert_int(Mirror.place_of(game.state, P1)).is_equal(place)
	assert_dict(FixtureMirror.shown(game, P1)).is_equal({place: P1})
	for peer: int in [P2, P3]:
		assert_array(FixtureMirror.told(game, peer)).is_equal(FixtureMirror.told(game, P1))


func test_two_players_hold_two_places_and_a_third_is_refused_at_a_held_one() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2, P3])
	FixtureMirror.use(game, P1, 0)
	FixtureMirror.use(game, P2, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	var held := {FixtureMirror.place(game, 0): P1, FixtureMirror.place(game, 1): P2}
	assert_dict(FixtureMirror.shown(game, P3)).is_equal(held)
	var told := FixtureMirror.told(game, P3).size()
	FixtureMirror.use(game, P3, 1, 3)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"unavailable"])
	assert_int(Mirror.place_of(game.state, P3)).is_equal(-1)
	assert_int(FixtureMirror.told(game, P3).size()).is_equal(told)


func test_the_holders_interact_again_gives_the_place_up() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	FixtureMirror.use(game, P1, 0)
	FixtureMirror.interact(game, P1, 0, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(Mirror.place_of(game.state, P1)).is_equal(-1)
	assert_dict(FixtureMirror.shown(game, P2)).is_empty()
	FixtureMirror.use(game, P2, 0, 3)
	assert_int(Mirror.place_of(game.state, P2)).is_equal(FixtureMirror.place(game, 0))


func test_an_interact_at_another_place_moves_the_holder() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	FixtureMirror.use(game, P1, 0)
	FixtureMirror.use(game, P1, 1, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_dict(FixtureMirror.shown(game, P2)).is_equal({FixtureMirror.place(game, 1): P1})


func test_an_interact_out_of_reach_takes_no_place() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1])
	FixtureItemModes.stand(game, P1, FixtureMirror.PLACES[0] + Vector3(3, 0, 0))
	FixtureMirror.interact(game, P1, 0)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_reach"])
	assert_int(Mirror.place_of(game.state, P1)).is_equal(-1)


func test_walking_away_gives_the_place_up() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	FixtureMirror.use(game, P1, 0)
	FixtureItemModes.stand(game, P1, FixtureMirror.PLACES[0] + Vector3(2, 0, 0))
	FixtureModes.run_ticks(game, 1)
	assert_int(Mirror.place_of(game.state, P1)).is_equal(-1)
	assert_dict(FixtureMirror.shown(game, P2)).is_empty()


func test_a_knockdown_a_death_and_a_limp_each_give_the_place_up() -> void:
	for how: String in ["downed", "dead", "limp"]:
		var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
		FixtureMirror.use(game, P1, 0)
		var player := game.state.player(P1)
		match how:
			"downed":
				player.life = PlayerState.Life.DOWNED
			"dead":
				player.life = PlayerState.Life.DEAD
			_:
				player.limp = LimpState.new(game.ticked_through() + 100)
		FixtureModes.run_ticks(game, 1)
		assert_int(Mirror.place_of(game.state, P1)).override_failure_message(how).is_equal(-1)
		assert_dict(FixtureMirror.shown(game, P2)).override_failure_message(how).is_empty()


func test_a_leave_gives_the_place_up() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	FixtureMirror.use(game, P1, 0)
	FixtureModes.send(game, Intents.PEER_LEFT, P1)
	FixtureModes.run_ticks(game, 1)
	assert_int(Mirror.place_of(game.state, P1)).is_equal(-1)
	assert_dict(FixtureMirror.shown(game, P2)).is_empty()


func test_no_place_survives_into_a_match() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	FixtureMirror.use(game, P1, 0)
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	FixtureLobbyHands.through_countdown(game)
	assert_str(game.phase_id()).is_equal("loading")
	assert_int(Mirror.place_of(game.state, P1)).is_equal(-1)
	assert_dict(FixtureMirror.shown(game, P2)).is_empty()


func test_a_cancelled_countdown_keeps_the_place() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	FixtureMirror.use(game, P1, 0)
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	FixtureModes.run_ticks(game, 2)
	assert_str(game.phase_id()).is_equal("countdown")
	FixtureBaseMode.ready(game, P2, false, 5)
	FixtureModes.run_ticks(game, 2)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_int(Mirror.place_of(game.state, P1)).is_equal(FixtureMirror.place(game, 0))


func test_a_joiner_is_told_the_places_in_use() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	FixtureMirror.use(game, P1, 0)
	FixtureBaseMode.join(game, P3)
	FixtureModes.run_ticks(game, 1)
	assert_dict(FixtureMirror.shown(game, P3)).is_equal({FixtureMirror.place(game, 0): P1})


func test_nothing_is_told_while_every_place_is_free() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	FixtureBaseMode.join(game, P3)
	FixtureModes.run_ticks(game, 3)
	for peer: int in [P1, P2, P3]:
		assert_array(FixtureMirror.told(game, peer)).is_empty()


## One place per player, so a mirror never holds more places in use than players: the wire's list
## cap is core's.
func test_the_wire_holds_as_many_places_as_the_mirror_allows() -> void:
	assert_int(WireSchema.MAX_MIRROR_PLACES).is_equal(Mirror.MAX_PLACES)
