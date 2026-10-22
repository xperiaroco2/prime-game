extends GdUnitTestSuite
## HostSession's snapshots over a LoopbackHub (ARCHITECTURE §4.5 "Snapshots", #1234): each avatar's
## record is encoded once per tick (SnapshotEncoder), and each client still decodes exactly the
## avatars view_of gives its peer, tick by tick: the others' only, and a knocked-down player its own
## as well (the knockdown rework's KE5).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_each_client_decodes_the_avatars_its_view_of_holds_a_downed_one_its_own() -> void:
	_h = Harness.new()
	_h.join()
	_h.join()
	_h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"round", 900)).is_true()
	_h.pump_seconds(0.5)
	var downed := _h.peer_of(_h.clients[1])
	_h.session.game.state.player(downed).life = PlayerState.Life.DOWNED
	_h.pump_seconds(0.5)
	# The host's own client and the three joined.
	assert_int(_h.clients.size()).is_equal(4)
	assert_bool(_h.own in _h.clients).is_true()
	for client: ClientSession in _h.clients:
		var peer := _h.peer_of(client)
		var snapshots: Dictionary = client.view.snapshots
		assert_array(snapshots.keys()).is_not_empty()
		var last_tick: int = snapshots.keys().max()
		var avatars: Dictionary = snapshots[last_tick]["avatars"]
		assert_int(avatars.size()).is_equal(4 if peer == downed else 3)
		assert_bool(avatars.has(peer)).is_equal(peer == downed)
		assert_array(_h.mismatches(client)).is_empty()
	assert_array(Array(_h.session.errors)).is_empty()
