extends GdUnitTestSuite
## ScenarioPeers (tests/harness/, ARCHITECTURE §9.7): a bot that left and joined again (P12 (a) of
## the returning-players ADR) is on a new peer; the map keeps its current one and maps each earlier
## one back to it, and a field naming that bot matches either.


func test_a_bot_on_a_new_peer_keeps_its_earlier_one() -> void:
	var peers := ScenarioPeers.core(3)
	assert_int(peers.peer_of(2)).is_equal(1002)
	peers.set_peer(2, 1004)
	assert_int(peers.peer_of(2)).is_equal(1004)
	assert_int(peers.bot_of(1004)).is_equal(2)
	assert_int(peers.bot_of(1002)).is_equal(2)
	assert_array(Array(peers.peers_of(2))).is_equal([1002, 1004])
	assert_array(Array(peers.peers_of(3))).is_equal([1003])
	assert_array(Array(peers.peers_of(5))).is_empty()
	assert_int(peers.bot_of(1005)).is_equal(0)
	# The current peers only.
	assert_dict(peers.to_dict()).is_equal({1: 1, 2: 1004, 3: 1003})


func test_reading_a_peer_again_changes_nothing() -> void:
	# An ENet instance reads the peer files again, in any order: an earlier peer read again does
	# not make it current.
	var peers := ScenarioPeers.new()
	peers.set_peer(2, 70)
	peers.set_peer(2, 80)
	peers.set_peer(2, 70)
	peers.set_peer(2, 80)
	assert_int(peers.peer_of(2)).is_equal(80)
	assert_array(Array(peers.peers_of(2))).is_equal([70, 80])


func test_a_fresh_peer_is_above_every_peer_ever_mapped() -> void:
	var peers := ScenarioPeers.core(3)
	assert_int(peers.fresh_peer()).is_equal(1004)
	peers.set_peer(3, peers.fresh_peer())
	peers.set_peer(3, 1001)
	assert_int(peers.fresh_peer()).is_equal(1005)
	assert_int(ScenarioPeers.new().fresh_peer()).is_equal(ScenarioPeers.PEER_BASE + 1)


func test_a_field_naming_a_bot_matches_each_of_its_peers() -> void:
	var peers := ScenarioPeers.core(2)
	peers.set_peer(2, 1003)
	var want := {"peer": 2}
	for peer: int in [1002, 1003]:
		var left := WireMessage.new(&"PlayerLeft", {"peer": peer})
		assert_bool(ScenarioPlay.matches_fields(left, null, &"PlayerLeft", want, peers)).is_true()
		var event := PlayerLeftEvent.new(peer)
		assert_bool(ScenarioPlay.event_matches(event, &"PlayerLeft", want, peers)).is_true()
	var other := WireMessage.new(&"PlayerLeft", {"peer": 1})
	assert_bool(ScenarioPlay.matches_fields(other, null, &"PlayerLeft", want, peers)).is_false()
	# A bot whose peer is not known yet names peer 0, as before.
	var unknown := WireMessage.new(&"PlayerLeft", {"peer": 0})
	(
		assert_bool(ScenarioPlay.matches_fields(unknown, null, &"PlayerLeft", {"peer": 7}, peers))
		. is_true()
	)
