extends GdUnitTestSuite
## A player who joins the lobby after a photo booth print sees the strips as the others do (#1474;
## ARCHITECTURE §3.5, §4.2, §9.5.29): over a LoopbackHub with a fake clock
## (host_session_harness.gd), the host's own player and a second client stand in the booth and the
## own player presses it; a later joiner decodes one BoothReplay, which no one else gets, and its
## BoothBook binds each strip to the frames the present players' books took live off the BoothStep
## FLASHes. Its decoded events are what view_of its peer holds.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
const OWN := 1

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


## FixtureBooth's mode with the harness's res:// levels and voice rules.
func _mode() -> GameMode:
	var made := FixtureBooth.mode()
	var levels := Harness.fixture_mode()
	made.lobby_level = levels.lobby_level
	made.maps = levels.maps
	for phase_id: StringName in [&"lobby", &"countdown", &"round"]:
		made.find_phase(phase_id).voice_rule = levels.find_phase(phase_id).voice_rule
	return made


## A BoothBook fed `client`'s decoded events, as ItemWorld feeds its own.
func _book_of(client: ClientSession) -> BoothBook:
	var book := BoothBook.new()
	client.event_received.connect(book.fold)
	return book


func test_a_lobby_joiner_binds_the_strips_to_the_frames_the_others_saw() -> void:
	var layouts := Harness.layouts()
	layouts[Harness.LOBBY].add_marker(&"booth", FixtureBooth.BOOTH)
	_h = Harness.new(_mode(), true, null, layouts)
	assert_bool(_h.started).is_true()
	var own_book := _book_of(_h.own)
	var friend := _h.join()
	var friend_book := _book_of(friend)
	_h.pump_frames(6)
	assert_bool(_h.welcome_all()).is_true()
	var game := _h.session.game
	var friend_peer := friend.model.own_peer
	FixtureItemModes.stand(game, OWN, FixtureBooth.inside(1))
	FixtureItemModes.stand(game, friend_peer, FixtureBooth.inside(2))
	var booth := FixtureBooth.booth_id(game)
	assert_int(booth).is_greater_equal(0)
	assert_int(_h.own.send_intent(Intents.INTERACT, {"station": booth, "item": -1})).is_greater(0)
	_h.pump_seconds(3.0)
	var printed := FixtureBooth.steps_of(game, OWN, BoothStepEvent.PRINTED)
	assert_array(printed).has_size(1)
	var strips := printed[0].items
	assert_int(strips.size()).is_equal(2)
	var live := own_book.session_of(strips[1])
	assert_object(live).is_not_null()
	assert_int(live.frame_count()).is_equal(FixtureBooth.FRAMES)
	var joiner := _h.join()
	var joiner_book := _book_of(joiner)
	_h.pump_frames(6)
	assert_bool(joiner.is_welcomed()).is_true()
	var replays := joiner.view.events_named(&"BoothReplay")
	assert_array(replays).has_size(1)
	assert_int(replays[0].fields["peer"] as int).is_equal(joiner.model.own_peer)
	assert_array(_h.own.view.events_named(&"BoothReplay")).is_empty()
	assert_array(friend.view.events_named(&"BoothReplay")).is_empty()
	for strip: int in strips:
		var shown := joiner_book.session_of(strip)
		assert_object(shown).is_not_null()
		assert_int(shown.state).is_equal(BoothBook.State.PRINTED)
		assert_int(shown.frame_count()).is_equal(FixtureBooth.FRAMES)
		for frame: int in FixtureBooth.FRAMES:
			assert_array(shown.record_of(frame)).is_equal(live.record_of(frame))
			assert_array(shown.record_of(frame)).is_equal(
				friend_book.session_of(strip).record_of(frame)
			)
			assert_int(shown.record_of(frame).size()).is_equal(2)
		assert_bool(joiner_book.take_fresh(strip)).is_false()
	assert_object(joiner_book.session_of(strips[0])).is_same(joiner_book.session_of(strips[1]))
	assert_array(_h.mismatches(joiner)).is_empty()
	assert_int(_h.session.bad_payloads).is_equal(0)
	assert_array(game.diagnostics).is_empty()
