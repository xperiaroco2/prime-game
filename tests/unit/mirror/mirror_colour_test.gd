extends GdUnitTestSuite
## The colour changes at the mirror (#1394; ARCHITECTURE §3.5, §7.1.23; GDD §3 "The mirror", in M8
## only the colour): in a lobby with mirror places a SetProfile asking for another colour from a
## player at no place is `not_at_mirror`, from a place it is applied and every peer sees it
## (ProfileChanged); two players at two places change at once; a colour another player has still
## gives the first free one (PlayerColours.resolve, kept); the name alone changes anywhere; the
## colour is kept when the match returns to the lobby. Driven by FixtureMirror.

const P1 := FixtureMirror.P1
const P2 := FixtureMirror.P2
const P3 := FixtureMirror.P3
## A colour no fixture player joins with.
const FREE := 7


func test_a_colour_change_away_from_the_mirror_is_refused() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	var before := game.state.player(P1).colour
	FixtureMirror.set_colour(game, P1, FREE)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([Mirror.NOT_AT_MIRROR])
	assert_int(game.state.player(P1).colour).is_equal(before)
	assert_array(game.view_of(P2).events_named(&"ProfileChanged")).is_empty()


func test_a_colour_change_at_a_place_is_applied_and_every_peer_sees_it() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	FixtureMirror.use(game, P1, 0)
	FixtureMirror.set_colour(game, P1, FREE, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(game.state.player(P1).colour).is_equal(FREE)
	for peer: int in [P1, P2]:
		var changed := game.view_of(peer).events_named(&"ProfileChanged")
		assert_int(changed.size()).is_equal(1)
		assert_int(changed[0].to_dict()["peer"]).is_equal(P1)
		assert_int(changed[0].to_dict()["colour"]).is_equal(FREE)


func test_two_players_at_two_places_change_at_once() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2, P3])
	FixtureMirror.use(game, P1, 0)
	FixtureMirror.use(game, P2, 1)
	FixtureModes.send(
		game, Intents.SET_PROFILE, P1, {"name": game.state.player(P1).name, "colour": FREE}, 2
	)
	FixtureModes.send(
		game, Intents.SET_PROFILE, P2, {"name": game.state.player(P2).name, "colour": FREE + 1}, 2
	)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P1).colour).is_equal(FREE)
	assert_int(game.state.player(P2).colour).is_equal(FREE + 1)
	assert_int(game.view_of(P3).events_named(&"ProfileChanged").size()).is_equal(2)


func test_a_colour_another_player_has_gives_the_first_free_one() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	FixtureMirror.use(game, P1, 0)
	var taken := game.state.player(P2).colour
	FixtureMirror.set_colour(game, P1, taken, 2)
	var colour := game.state.player(P1).colour
	assert_int(colour).is_not_equal(taken)
	var others: Array[int] = [taken]
	assert_int(colour).is_equal(PlayerColours.resolve(taken, others))


func test_the_name_alone_changes_away_from_the_mirror() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	var colour := game.state.player(P1).colour
	FixtureModes.send(game, Intents.SET_PROFILE, P1, {"name": "Olena", "colour": colour})
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_str(game.state.player(P1).name).is_equal("Olena")


func test_a_place_given_up_ends_the_colour_changes() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1])
	FixtureMirror.use(game, P1, 0)
	FixtureMirror.interact(game, P1, 0, 2)
	FixtureMirror.set_colour(game, P1, FREE, 3)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([Mirror.NOT_AT_MIRROR])


## The way back to the lobby keeps it too: join_rules_profile_test's
## test_colours_and_names_survive_the_way_back_to_the_lobby.
func test_the_colour_is_kept_into_the_match_with_the_place_given_up() -> void:
	var game := FixtureMirror.joined(FixtureMirror.mode(), [P1, P2])
	FixtureMirror.use(game, P1, 0)
	FixtureMirror.set_colour(game, P1, FREE, 2)
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	FixtureLobbyHands.through_countdown(game)
	assert_str(game.phase_id()).is_equal("loading")
	assert_int(Mirror.place_of(game.state, P1)).is_equal(-1)
	assert_int(game.state.player(P1).colour).is_equal(FREE)
