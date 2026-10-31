extends GdUnitTestSuite
## The booth's frames (#1396; ARCHITECTURE §9.4.5, §9.5.28): every living present player inside the
## booth station's cylinder when a flash fires is one row of its record, in peer order, with the
## public look and body state it has at that tick (so a pose changed between flashes shows at the
## next one); a player outside by a hair, above it, downed or dead is not; a limp one is, with its
## bit. Every lobby peer gets the same FLASH. Driven by FixtureBooth.

const P1 := FixtureBooth.P1
const P2 := FixtureBooth.P2
const P3 := FixtureBooth.P3
const FLASH := BoothStepEvent.FLASH


## The flashes of a session P1 starts in `game`, all of them fired.
func _all_flashes(game: Match) -> Array[BoothStepEvent]:
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	return FixtureBooth.steps_of(game, P1, FLASH)


func test_a_flash_records_everyone_inside_in_peer_order() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P3, P1, P2])
	var flashes := _all_flashes(game)
	assert_array(flashes).has_size(FixtureBooth.FRAMES)
	for flash: BoothStepEvent in flashes:
		assert_array(FixtureBooth.peers_of(flash)).is_equal([P1, P2, P3])


func test_a_row_holds_the_public_look_of_its_player() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	var facing := Vector3(1, 0, 0)
	game.state.player(P2).facing = facing
	var flashes := _all_flashes(game)
	var row: Dictionary = flashes[0].record[1]
	assert_int(row["peer"] as int).is_equal(P2)
	assert_int(row["colour"] as int).is_equal(game.state.player(P2).colour)
	assert_vector(row["position"] as Vector3).is_equal(FixtureBooth.inside(P2))
	assert_vector(row["facing"] as Vector3).is_equal(facing)
	for bit: String in ["crouched", "sneaking", "posed", "limp"]:
		assert_bool(row[bit] as bool).is_false()


func test_a_player_just_outside_or_above_is_not_in_the_frame() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2, P3])
	var edge := FixtureBooth.RADIUS
	FixtureItemModes.stand(game, P2, FixtureBooth.BOOTH + Vector3(0, 0, edge + 0.01))
	FixtureItemModes.stand(game, P3, FixtureBooth.BOOTH + Vector3(0, FixtureBooth.HEIGHT + 0.01, 0))
	var flashes := _all_flashes(game)
	assert_array(FixtureBooth.peers_of(flashes[0])).is_equal([P1])
	# On the rim is still inside.
	var rim := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureItemModes.stand(rim, P2, FixtureBooth.BOOTH + Vector3(0, 0, edge - 0.01))
	assert_array(FixtureBooth.peers_of(_all_flashes(rim)[0])).is_equal([P1, P2])


func test_a_downed_or_dead_player_is_not_in_the_frame_and_a_limp_one_is() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2, P3])
	game.state.player(P2).life = PlayerState.Life.DOWNED
	var limp := game.state.player(P3)
	limp.limp = LimpState.new(game.ticked_through() + 1000)
	var flashes := _all_flashes(game)
	assert_array(FixtureBooth.peers_of(flashes[0])).is_equal([P1, P3])
	assert_bool(flashes[0].record[1]["limp"] as bool).is_true()
	var dead := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	dead.state.player(P2).life = PlayerState.Life.DEAD
	assert_array(FixtureBooth.peers_of(_all_flashes(dead)[0])).is_equal([P1])


func test_the_record_at_flash_k_holds_the_body_at_flash_k() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2, P3])
	var p2 := game.state.player(P2)
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.COUNTDOWN + 1)
	# Between flash 0 and flash 1: P2 crouches and turns, P1 sneaks.
	p2.crouched = true
	p2.facing = Vector3(0, 0, 1)
	game.state.player(P1).sneaking = true
	FixtureModes.run_ticks(game, FixtureBooth.GAP)
	# Between flash 1 and flash 2: P2 stands and takes the seated pose, P1 goes limp, P3 steps out.
	p2.crouched = false
	p2.posed = true
	game.state.player(P1).limp = LimpState.new(game.ticked_through() + 1000)
	FixtureModes.run_ticks(game, FixtureBooth.GAP - 1)
	FixtureItemModes.stand(game, P3, FixtureBooth.BOOTH + Vector3(5, 0, 0))
	FixtureModes.run_ticks(game, 1)
	var flashes := FixtureBooth.steps_of(game, P1, FLASH)
	assert_array(flashes).has_size(FixtureBooth.FRAMES)
	var first: Dictionary = flashes[0].record[1]
	assert_bool(first["crouched"] as bool).is_false()
	assert_vector(first["facing"] as Vector3).is_equal(Vector3.FORWARD)
	assert_bool(flashes[0].record[0]["sneaking"] as bool).is_false()
	var second: Dictionary = flashes[1].record[1]
	assert_bool(second["crouched"] as bool).is_true()
	assert_bool(second["posed"] as bool).is_false()
	assert_vector(second["facing"] as Vector3).is_equal(Vector3(0, 0, 1))
	assert_bool(flashes[1].record[0]["sneaking"] as bool).is_true()
	assert_bool(flashes[1].record[0]["limp"] as bool).is_false()
	assert_bool(flashes[1].record[1]["posed"] as bool).is_false()
	assert_array(FixtureBooth.peers_of(flashes[2])).is_equal([P1, P2])
	var third: Dictionary = flashes[2].record[1]
	assert_bool(third["posed"] as bool).is_true()
	assert_bool(third["crouched"] as bool).is_false()
	assert_bool(flashes[2].record[0]["limp"] as bool).is_true()


func test_every_lobby_peer_gets_the_same_flash() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBaseMode.join(game, P3)
	FixtureItemModes.stand(game, P3, FixtureBooth.BOOTH + Vector3(8, 0, 0))
	var flashes := _all_flashes(game)
	for peer: int in [P2, P3]:
		var seen := FixtureBooth.steps_of(game, peer, FLASH)
		assert_array(seen).has_size(flashes.size())
		for k in seen.size():
			assert_dict(seen[k].to_dict()).is_equal(flashes[k].to_dict())


func test_a_flash_with_nobody_inside_is_empty_and_prints_nothing() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBooth.press(game, P1)
	for peer: int in [P1, P2]:
		FixtureItemModes.stand(game, peer, FixtureBooth.BOOTH + Vector3(6, 0, peer))
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	for flash: BoothStepEvent in FixtureBooth.steps_of(game, P2, FLASH):
		assert_array(flash.record).is_empty()
	assert_array(FixtureBooth.steps_of(game, P2, BoothStepEvent.STOPPED)).has_size(1)
	assert_array(FixtureBooth.steps_of(game, P2, BoothStepEvent.PRINTED)).is_empty()
	assert_array(game.view_of(P2).events_named(&"ItemSpawned")).is_empty()
	assert_array(game.diagnostics).is_empty()
