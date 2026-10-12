extends GdUnitTestSuite
## A returning player over the wire (ARCHITECTURE §3.5, the returning-players ADR, #638): a client
## that left and joins again with the same return key gets its old Player<n> back in every client's
## roster, a return does not count toward the joins, and a key a present player holds joins as a
## new number. Over a LoopbackHub with a fake clock (host_session_harness.gd).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
const KEY_A := "0123456789abcdef0123456789abcdef"
const KEY_B := "fedcba9876543210fedcba9876543210"

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_a_return_gets_its_old_number_in_every_roster() -> void:
	_h = Harness.new()
	var first := _h.join(null, "", KEY_A)
	assert_bool(_h.welcome_all()).is_true()
	var second := _h.join(null, "", KEY_B)
	assert_bool(_h.welcome_all()).is_true()
	assert_str(second.model.roster[_h.peer_of(first)].name).is_equal("Player2")
	var first_peer := _h.peer_of(first)
	first.leave()
	var gone := func() -> bool: return not _h.session.game.state.is_present(first_peer)
	assert_bool(_h.pump_until(gone, 60)).is_true()
	var back := _h.join(null, "", KEY_A)
	assert_bool(_h.welcome_all()).is_true()
	var newcomer := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(4)
	var expected := {
		1: "Player1",
		_h.peer_of(second): "Player3",
		_h.peer_of(back): "Player2",
		_h.peer_of(newcomer): "Player4",
	}
	assert_int(_h.peer_of(back)).is_not_equal(2)
	for client: ClientSession in [_h.own, second, back, newcomer]:
		var names := {}
		for peer: int in client.model.roster:
			names[peer] = client.model.roster[peer].name
		assert_dict(names).override_failure_message(str(names)).is_equal(expected)
		assert_array(_h.mismatches(client)).is_empty()
	assert_int(_h.session.game.state.joins).is_equal(4)


func test_a_second_window_with_a_present_players_key_joins_as_a_new_number() -> void:
	_h = Harness.new()
	var first := _h.join(null, "", KEY_A)
	assert_bool(_h.welcome_all()).is_true()
	var twin := _h.join(null, "", KEY_A)
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(4)
	assert_bool(_h.session.game.state.is_present(_h.peer_of(first))).is_true()
	assert_str(_h.own.model.roster[_h.peer_of(first)].name).is_equal("Player2")
	assert_str(_h.own.model.roster[_h.peer_of(twin)].name).is_equal("Player3")
	assert_bool(first.is_ended()).is_false()
	# The key keeps its first binding: the first window, once gone, comes back as Player2.
	var first_peer := _h.peer_of(first)
	first.leave()
	var gone := func() -> bool: return not _h.session.game.state.is_present(first_peer)
	assert_bool(_h.pump_until(gone, 60)).is_true()
	var back := _h.join(null, "", KEY_A)
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(4)
	assert_str(_h.own.model.roster[_h.peer_of(back)].name).is_equal("Player2")
	assert_array(_h.mismatches(_h.own)).is_empty()
