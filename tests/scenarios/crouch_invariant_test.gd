extends GdUnitTestSuite
## The crouch invariant (ScenarioInvariants.crouch_problem, the crouch ADR, KE1, KE10, #790) over
## snapshots of a fixture match whose state is set by hand: a crouched living player on a map the
## crouch plays on passes; a crouched downed player, a crouch on a map crouch_maps does not list
## and a crouch in the lobby are each caught.

const P1 := 1
const P2 := 2


func _avatar(game: Match, of: int) -> Dictionary:
	var avatars: Dictionary = game.snapshot_for(P1).get("avatars", {})
	return avatars.get(of, {})


func test_a_crouched_living_player_on_a_crouch_map_passes() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	game.state.player(P2).crouched = true
	assert_bool(_avatar(game, P2)["crouched"] as bool).is_true()
	assert_str(ScenarioInvariants.crouch_problem(game, P2, _avatar(game, P2))).is_empty()
	game.mode.player_rules.crouch_maps = PackedStringArray([FixtureModes.MAP])
	assert_str(ScenarioInvariants.crouch_problem(game, P2, _avatar(game, P2))).is_empty()


func test_a_standing_avatar_passes_anywhere() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1, P2])
	assert_str(ScenarioInvariants.crouch_problem(game, P2, _avatar(game, P2))).is_empty()


func test_a_crouched_downed_player_is_caught() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	game.state.player(P2).life = PlayerState.Life.DOWNED
	game.state.player(P2).crouched = true
	var problem := ScenarioInvariants.crouch_problem(game, P2, _avatar(game, P2))
	assert_str(problem).contains("not alive")


func test_a_crouch_on_a_map_crouch_maps_does_not_list_is_caught() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	game.mode.player_rules.crouch_maps = PackedStringArray(["fixture://elsewhere"])
	game.state.player(P2).crouched = true
	var problem := ScenarioInvariants.crouch_problem(game, P2, _avatar(game, P2))
	assert_str(problem).contains("a map without the crouch")


func test_a_crouch_in_the_lobby_is_caught() -> void:
	# The lobby's state.map already holds the next match's pick, a map the crouch plays on.
	var game := FixtureModes.started(FixtureModes.basic(), [P1, P2])
	game.state.player(P2).crouched = true
	var problem := ScenarioInvariants.crouch_problem(game, P2, _avatar(game, P2))
	assert_str(problem).contains("a phase off the match's map")
