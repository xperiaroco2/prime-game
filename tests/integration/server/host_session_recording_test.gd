extends GdUnitTestSuite
## What the host keeps (#1191; ARCHITECTURE §3.3, §4.5.10): a release build writes no replay, so
## its match keeps no command, no WorldQuery answer and no delivered event however long the session
## runs, and still delivers; a debug build keeps them for its replay; HostNode.skip_replay() stops
## the keeping. Over a LoopbackHub with a fake clock (host_session_harness.gd).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
const SECONDS := 3.0

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_a_release_host_keeps_no_log_and_still_delivers() -> void:
	_h = Harness.new(null, true, null, {}, true)
	assert_bool(_h.started).is_true()
	var joined := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_seconds(SECONDS)
	var game := _h.session.game
	assert_bool(game.recording).is_false()
	assert_int(game.ticked_through()).is_greater(Ticks.RATE * 2)
	assert_array(game.command_log.commands).is_empty()
	assert_array(game.command_log.world_answers).is_empty()
	assert_array(game.emitted()).is_empty()
	# Delivery does not need the log: both clients were welcomed and see each other.
	assert_bool(_h.own.is_welcomed()).is_true()
	assert_bool(joined.is_welcomed()).is_true()
	assert_bool(_h.own.model.roster.has(_h.peer_of(joined))).is_true()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_debug_host_keeps_the_log_for_its_replay() -> void:
	_h = Harness.new()
	_h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_seconds(SECONDS)
	var game := _h.session.game
	assert_bool(game.recording).is_true()
	# PeerConnected and Hello of both clients at least.
	assert_int(game.command_log.commands.size()).is_greater_equal(4)
	# Each idle client's claims ask the floor (ARCHITECTURE §7.1): the answers grow with time too.
	assert_array(game.command_log.world_answers).is_not_empty()
	assert_array(game.emitted()).is_not_empty()


func test_skip_replay_stops_the_keeping() -> void:
	_h = Harness.new()
	_h.join()
	assert_bool(_h.welcome_all()).is_true()
	assert_array(_h.session.game.command_log.commands).is_not_empty()
	var node: HostNode = auto_free(HostNode.new(_h.session))
	node.skip_replay()
	var game := _h.session.game
	assert_bool(game.recording).is_false()
	assert_str(_h.session.replay_dir).is_empty()
	assert_array(game.command_log.commands).is_empty()
	_h.pump_seconds(SECONDS)
	assert_array(game.command_log.commands).is_empty()
	assert_array(game.command_log.world_answers).is_empty()
