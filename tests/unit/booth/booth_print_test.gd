extends GdUnitTestSuite
## The booth's print (#1396; ARCHITECTURE §9.4.5, §9.5.29): after the last flash, one strip for each
## player in any frame who is still the same player, present and alive, given as GiveItem gives
## (the hand, else the belt, else the feet); PRINTED names the strips, the ids ItemSpawned
## announced, in peer order. A player of frame 1 who left before the print gets none and no rule
## error is logged; the strip's cap vanishes the longest-lying loose strip first. Driven by
## FixtureBooth.

const P1 := FixtureBooth.P1
const P2 := FixtureBooth.P2
const P3 := FixtureBooth.P3
const PRINTED := BoothStepEvent.PRINTED


## P1 presses and the whole session runs.
func _session(game: Match, seq := 0) -> void:
	FixtureBooth.press(game, P1, seq)
	FixtureModes.run_ticks(game, FixtureBooth.whole())


## The ids ItemSpawned announced to `peer`, in order.
func _spawned(game: Match, peer: int) -> PackedInt32Array:
	var found := PackedInt32Array()
	for event: MatchEvent in game.view_of(peer).events_named(&"ItemSpawned"):
		found.append((event as ItemSpawnedEvent).item)
	return found


func test_each_player_in_the_frames_gets_a_strip_in_the_hand() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2, P3])
	_session(game)
	var printed := FixtureBooth.steps_of(game, P3, PRINTED)
	assert_array(printed).has_size(1)
	assert_array(Array(printed[0].items)).is_equal(Array(_spawned(game, P3)))
	assert_int(printed[0].items.size()).is_equal(3)
	var peers: Array[int] = [P1, P2, P3]
	for k in peers.size():
		var player := game.state.player(peers[k])
		var strip: ItemState = game.state.items[printed[0].items[k]]
		assert_int(player.held_item).is_equal(strip.id)
		assert_str(String(strip.kind.id)).is_equal("strip")
		assert_int(strip.where).is_equal(ItemState.Where.HAND)
	assert_array(game.diagnostics).is_empty()


func test_a_second_strip_goes_to_the_hand_and_the_first_onto_the_belt() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	_session(game)
	var first := game.state.player(P1).held_item
	_session(game, 1)
	var player := game.state.player(P1)
	var second := FixtureBooth.steps_of(game, P1, PRINTED)[1].items[0]
	assert_int(player.held_item).is_equal(second)
	assert_bool(player.belt_places().has(player.place_of(first))).is_true()
	assert_int(game.state.items[first].where).is_equal(ItemState.Where.BELT)


func test_a_player_in_the_frames_only_early_still_gets_a_strip() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.COUNTDOWN + 1)
	FixtureItemModes.stand(game, P2, FixtureBooth.BOOTH + Vector3(6, 0, 0))
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	var printed := FixtureBooth.steps_of(game, P1, PRINTED)
	assert_int(printed[0].items.size()).is_equal(2)
	assert_int(game.state.player(P2).held_item).is_equal(printed[0].items[1])


func test_a_player_of_frame_one_who_left_gets_no_strip() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2, P3])
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.COUNTDOWN + 1)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	var printed := FixtureBooth.steps_of(game, P1, PRINTED)
	assert_array(printed).has_size(1)
	assert_int(printed[0].items.size()).is_equal(2)
	assert_int(game.state.player(P1).held_item).is_equal(printed[0].items[0])
	assert_int(game.state.player(P3).held_item).is_equal(printed[0].items[1])
	assert_array(game.diagnostics).is_empty()


func test_a_player_downed_before_the_print_gets_no_strip() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.COUNTDOWN + 1)
	game.state.player(P2).life = PlayerState.Life.DOWNED
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	var printed := FixtureBooth.steps_of(game, P1, PRINTED)
	assert_int(printed[0].items.size()).is_equal(1)
	assert_int(game.state.player(P2).held_item).is_equal(-1)


func test_the_cap_vanishes_the_longest_lying_loose_strip() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1])
	var oldest := FixtureItemModes.lay(game, &"strip", Vector3(4, 0, 4))
	oldest.rest_tick = 1
	for k in FixtureBooth.STRIPS - 2:
		var lying := FixtureItemModes.lay(game, &"strip", Vector3(4, 0, 5 + k))
		lying.rest_tick = 10 + k
	# One held by P1 makes the cap full.
	_session(game)
	assert_bool(game.state.items.has(oldest.id)).is_true()
	_session(game, 1)
	assert_bool(game.state.items.has(oldest.id)).is_false()
	var vanished := game.view_of(P1).events_named(&"ItemVanished")
	assert_array(vanished).has_size(1)
	assert_int((vanished[0] as ItemVanishedEvent).item).is_equal(oldest.id)
	assert_array(FixtureBooth.steps_of(game, P1, PRINTED)).has_size(2)


func test_a_rejoiner_with_the_peer_id_of_a_leaver_gets_no_strip() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.COUNTDOWN + 1)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	FixtureBaseMode.join(game, P2)
	FixtureItemModes.stand(game, P2, FixtureBooth.BOOTH + Vector3(6, 0, 0))
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	var printed := FixtureBooth.steps_of(game, P1, PRINTED)
	assert_int(printed[0].items.size()).is_equal(1)
	assert_int(game.state.player(P2).held_item).is_equal(-1)
	assert_array(game.diagnostics).is_empty()


func test_a_rejoiner_with_the_peer_id_of_a_leaver_gets_a_strip_for_its_own_frames() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.COUNTDOWN + 1)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	FixtureBaseMode.join(game, P2)
	FixtureItemModes.stand(game, P2, FixtureBooth.inside(P2))
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	var printed := FixtureBooth.steps_of(game, P1, PRINTED)
	assert_int(printed[0].items.size()).is_equal(2)
	var rejoiner := game.state.player(P2)
	assert_int(rejoiner.held_item).is_equal(printed[0].items[1])
	assert_array(game.diagnostics).is_empty()
