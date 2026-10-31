extends GdUnitTestSuite
## The booth FLASH record invariant of ScenarioInvariants (#1396; ARCHITECTURE §5, "invariants that
## do not trust the declarations"): a row must name a present, living peer once, at the position it
## has, inside the booth's cylinder. A frame that kept a downed player, a stale position or someone
## outside would pass the bots without it.

const P1 := FixtureBooth.P1
const P2 := FixtureBooth.P2


func _setup() -> Array:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	var station: StationState = game.state.stations[FixtureBooth.booth_id(game)]
	var rows := BoothSessions.frame_of(game.state, station)
	return [game, station, rows]


func _positions(game: Match) -> Dictionary:
	var positions: Dictionary = {}
	for peer: int in game.state.present_peers():
		positions[peer] = game.state.player(peer).position
	return positions


func _found(setup: Array, rows: Array, living: Array[int]) -> PackedStringArray:
	var game: Match = setup[0]
	return ScenarioInvariants.flash_problems(
		rows, setup[1] as StationState, PackedInt32Array(living), _positions(game)
	)


func test_an_honest_frame_has_no_problem() -> void:
	var setup := _setup()
	assert_array(Array(_found(setup, setup[2] as Array, [P1, P2]))).is_empty()


func test_a_row_of_a_downed_peer_is_a_problem() -> void:
	var setup := _setup()
	var found := _found(setup, setup[2] as Array, [P1])
	assert_str(" ".join(found)).contains("not present and alive")


func test_a_row_at_a_stale_position_is_a_problem() -> void:
	var setup := _setup()
	var rows: Array = (setup[2] as Array).duplicate(true)
	(rows[0] as Dictionary)["position"] = FixtureBooth.inside(P1) + Vector3(0.2, 0, 0)
	assert_str(" ".join(_found(setup, rows, [P1, P2]))).contains("not at")


func test_a_peer_named_twice_is_a_problem() -> void:
	var setup := _setup()
	var rows: Array = (setup[2] as Array).duplicate(true)
	rows.append(rows[0])
	assert_str(" ".join(_found(setup, rows, [P1, P2]))).contains("twice")


func test_a_peer_outside_the_booth_is_a_problem() -> void:
	var setup := _setup()
	var game: Match = setup[0]
	var away := FixtureBooth.BOOTH + Vector3(6, 0, 0)
	FixtureItemModes.stand(game, P2, away)
	var rows: Array = (setup[2] as Array).duplicate(true)
	(rows[1] as Dictionary)["position"] = away
	assert_str(" ".join(_found(setup, rows, [P1, P2]))).contains("outside the booth")
