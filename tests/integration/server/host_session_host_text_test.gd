extends GdUnitTestSuite
## Host text over the host session (ARCHITECTURE §4.2, §4.3, #548): every client decodes the same
## shortfalls as ids plus arguments (no sentence of the host's), a join updates them, and the end
## of a match gives every client the same reason, the id of the win condition that ended it. Each
## client's decoded events equal view_of its peer. Over a LoopbackHub with a fake clock
## (host_session_harness.gd).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
const WireSamples := preload("res://tests/unit/net/messages/wire_samples.gd")

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_every_client_reads_the_same_player_shortfall_until_enough_joined() -> void:
	var mode := Harness.fixture_mode()
	mode.min_players = 3
	_h = Harness.new(mode)
	_h.pump_frames(4)
	assert_bool(WireSamples.same(_h.own.model.shortfalls, _few(2, mode))).is_true()
	_h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(4)
	for client: ClientSession in _h.clients:
		assert_bool(WireSamples.same(client.model.shortfalls, _few(1, mode))).is_true()
		var changed := client.view.events_named(&"SettingsChanged")
		assert_bool(WireSamples.same(changed[-1].fields["shortfalls"], _few(1, mode))).is_true()
	_h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(4)
	for client: ClientSession in _h.clients:
		assert_array(client.model.shortfalls).is_empty()
		assert_array(_h.mismatches(client)).is_empty()
	assert_int(_h.session.bad_payloads).is_equal(0)


func test_every_client_gets_the_reason_the_match_ended() -> void:
	var mode := Harness.fixture_mode()
	mode.find_transition(&"round", Match.WON).actions = [EndMatch.new()]
	_h = Harness.new(mode)
	_h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_seconds(0.5)
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"round", 800)).is_true()
	_h.session.game.state.add_to_counter(0, &"crew_win", 1)
	assert_bool(_h.run_until_phase(&"end", 3)).is_true()
	_h.pump_frames(4)
	# The fixture's win condition is named after its side; no clock ran, so no time.
	var reason := mode.win_conditions[0].id
	var none: Dictionary[StringName, int] = {}
	var want := {"side": &"crew", "reason": reason, "numbers": none}
	for client: ClientSession in _h.clients:
		assert_str(String(client.model.winner)).is_equal("crew")
		assert_str(String(client.model.ended_by)).is_equal(String(reason))
		assert_int(client.model.round_seconds).is_equal(-1)
		var ended := client.view.events_named(&"MatchEnded")
		assert_int(ended.size()).is_equal(1)
		assert_bool(WireSamples.same(ended[0].fields, want)).is_true()
		assert_array(_h.mismatches(client)).is_empty()


## The shortfall of `count` players missing, as every client decodes it.
func _few(count: int, mode: GameMode) -> Array[Dictionary]:
	var numbers: Dictionary[StringName, int] = {
		&"count": count, &"min": mode.min_players, &"max": mode.max_players
	}
	return [{"id": &"players_few", "ids": PackedStringArray(), "numbers": numbers}]
