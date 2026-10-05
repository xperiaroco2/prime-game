extends GdUnitTestSuite
## NetTransport's inbox with a scripted backend: the order and the once-only rules of its signals,
## whatever the backend pushes (ENet can push HOST_LOST twice in one poll), and the LATEST lane's
## newest-only rule on the decode path (a peer's backlog after a freeze, #70).

const EVENT := 10
const INTENT := 11
const POSE := 12  # client -> host, latest
const STATE := 13  # host -> client, latest
const AIM := 14  # both ways, latest
const TALK := 15  # both ways, voice
const RELIABLE := MultiplayerPeer.TRANSFER_MODE_RELIABLE
const HOST_LOST := NetTransport.Inbound.Type.HOST_LOST
const PACKET := NetTransport.Inbound.Type.PACKET

var _kinds: NetKindTable


## A backend that pushes whatever the test queued, on the next poll.
class ScriptedTransport:
	extends NetTransport
	var queued: Array[NetTransport.Inbound] = []

	func queue(
		item_type: NetTransport.Inbound.Type, peer_id: int, bytes := PackedByteArray()
	) -> void:
		queued.append(NetTransport.Inbound.new(item_type, peer_id, bytes))

	## A framed message of kind on its own lane, as a backend receives it.
	func queue_message(peer_id: int, kind: int, payload: PackedByteArray) -> void:
		queue_on(peer_id, NetFrame.encode(kind, payload), _kinds.lane_of(kind))

	## Raw bytes arriving on a lane's channel and mode.
	func queue_on(peer_id: int, bytes: PackedByteArray, lane: NetKindTable.Lane) -> void:
		var channel := NetKindTable.channel_of(lane)
		var mode := NetKindTable.mode_of(lane)
		queued.append(NetTransport.Inbound.new(PACKET, peer_id, bytes, channel, mode))

	func _backend_host(_port: int, _max_clients: int) -> Error:
		return OK

	func _backend_join(_address: String, _port: int) -> Error:
		return OK

	func _backend_poll() -> void:
		for item in queued:
			_push(item)
		queued.clear()


class Counter:
	extends RefCounted
	var events: Array[String] = []

	func _init(transport: NetTransport) -> void:
		transport.connected.connect(
			func(own_id: int) -> void: events.append("connected %d" % own_id)
		)
		transport.connect_failed.connect(
			func(reason: StringName) -> void: events.append(String(reason))
		)
		transport.peer_joined.connect(
			func(peer_id: int) -> void: events.append("joined %d" % peer_id)
		)
		transport.peer_left.connect(func(peer_id: int) -> void: events.append("left %d" % peer_id))
		transport.host_lost.connect(func() -> void: events.append("host_lost"))
		transport.packet_received.connect(
			func(from_peer: int, kind: int, payload: PackedByteArray) -> void:
				var text := "packet %d:%d" % [from_peer, kind]
				events.append(text + (":%d" % payload[0] if payload.size() > 0 else ""))
		)


func before_test() -> void:
	_kinds = NetKindTable.new()
	_kinds.add(EVENT, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.HOST_TO_CLIENT, 8)
	_kinds.add(INTENT, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.CLIENT_TO_HOST, 8)
	_kinds.add(POSE, NetKindTable.Lane.LATEST, NetKindTable.Direction.CLIENT_TO_HOST, 8)
	_kinds.add(STATE, NetKindTable.Lane.LATEST, NetKindTable.Direction.HOST_TO_CLIENT, 8)
	_kinds.add(AIM, NetKindTable.Lane.LATEST, NetKindTable.Direction.BOTH, 8)
	_kinds.add(TALK, NetKindTable.Lane.VOICE, NetKindTable.Direction.BOTH, 8)


func test_host_lost_fires_once_for_two_reports() -> void:
	var client := _connected_client()
	var counter := Counter.new(client)
	client.queue(HOST_LOST, 1)
	client.queue(HOST_LOST, 1)
	client.poll()
	assert_array(counter.events).is_equal(["host_lost"])


func test_a_rejoin_from_a_handler_does_not_see_the_old_session() -> void:
	var client := _connected_client()
	var counter := Counter.new(client)
	client.host_lost.connect(func() -> void: client.join("elsewhere", 1))
	client.queue(HOST_LOST, 1)
	client.queue(HOST_LOST, 1)
	client.poll()
	assert_array(counter.events).is_equal(["host_lost"])
	assert_int(client.role()).is_equal(NetTransport.Role.CLIENT)


func test_host_lost_before_connected_is_a_failed_join() -> void:
	var client := ScriptedTransport.new(_kinds)
	client.join("somewhere", 1)
	var counter := Counter.new(client)
	client.queue(HOST_LOST, 1)
	client.poll()
	assert_array(counter.events).is_equal(["connect_failed"])


func test_packets_count_only_while_their_peer_is_connected() -> void:
	var host := ScriptedTransport.new(_kinds)
	host.host(1, 8)
	var counter := Counter.new(host)
	var intent := NetFrame.encode(INTENT, PackedByteArray())
	host.queue(NetTransport.Inbound.Type.PACKET, 5, intent)
	host.queue(NetTransport.Inbound.Type.JOINED, 5)
	host.queue(NetTransport.Inbound.Type.PACKET, 5, intent)
	host.queue(NetTransport.Inbound.Type.LEFT, 5)
	host.queue(NetTransport.Inbound.Type.PACKET, 5, intent)
	host.poll()
	assert_array(counter.events).is_equal(["joined 5", "packet 5:%d" % INTENT, "left 5"])
	assert_int(host.rejects.of_reason(NetRejects.Reason.UNKNOWN_PEER)).is_equal(2)


func test_a_rehost_from_a_handler_does_not_see_the_old_session() -> void:
	var host := ScriptedTransport.new(_kinds)
	host.host(1, 8)
	host.queue(NetTransport.Inbound.Type.JOINED, 5)
	host.poll()
	var counter := Counter.new(host)
	host.peer_left.connect(
		func(_peer_id: int) -> void:
			host.close()
			host.host(2, 8)
	)
	host.queue(NetTransport.Inbound.Type.LEFT, 5)
	host.queue(NetTransport.Inbound.Type.JOINED, 6)
	host.poll()
	assert_array(counter.events).is_equal(["left 5"])
	assert_array(Array(host.peers())).is_empty()


func test_a_backlog_on_the_latest_lane_delivers_only_the_newest_per_peer_and_kind() -> void:
	var host := _host_with([5, 6])
	var counter := Counter.new(host)
	# A 5 s freeze of the host: 100 claims from each client, 20 Hz, arrive in one poll, with the
	# reliable intents sent meanwhile and a second LATEST kind.
	for i in 100:
		host.queue_message(5, POSE, PackedByteArray([i]))
		host.queue_message(6, POSE, PackedByteArray([100 + i]))
		if i % 25 == 0:
			host.queue_message(5, INTENT, PackedByteArray([i]))
			host.queue_message(5, AIM, PackedByteArray([i]))
	host.poll()
	# Peer 5's intents split its backlog into runs, each merged into its newest message, so each
	# intent follows the claim sent just before it. Peer 6's intents-free backlog is one run.
	(
		assert_array(counter.events)
		. is_equal(
			[
				"packet 5:%d:0" % POSE,
				"packet 5:%d:0" % INTENT,
				"packet 5:%d:0" % AIM,
				"packet 5:%d:25" % POSE,
				"packet 5:%d:25" % INTENT,
				"packet 5:%d:25" % AIM,
				"packet 5:%d:50" % POSE,
				"packet 5:%d:50" % INTENT,
				"packet 5:%d:50" % AIM,
				"packet 5:%d:75" % POSE,
				"packet 5:%d:75" % INTENT,
				"packet 5:%d:75" % AIM,
				"packet 5:%d:99" % POSE,
				"packet 6:%d:199" % POSE,
			]
		)
	)
	assert_int(host.latest_superseded).is_equal(95 + 99)
	assert_int(host.rejects.total()).is_equal(0)


func test_only_a_reliable_message_from_the_same_peer_separates_its_runs() -> void:
	var host := _host_with([5, 6])
	var counter := Counter.new(host)
	# Peer 6's intent, peer 5's voice and a malformed reliable packet from peer 5 separate nothing.
	var trailing := NetFrame.encode(INTENT, PackedByteArray([9]))
	trailing.append(0)
	host.queue_message(5, POSE, PackedByteArray([1]))
	host.queue_message(6, INTENT, PackedByteArray([1]))
	host.queue_message(5, TALK, PackedByteArray([1]))
	host.queue_on(5, trailing, NetKindTable.Lane.RELIABLE)
	host.queue_message(5, POSE, PackedByteArray([2]))
	host.poll()
	assert_array(counter.events).is_equal(
		["packet 6:%d:1" % INTENT, "packet 5:%d:1" % TALK, "packet 5:%d:2" % POSE]
	)
	assert_int(host.latest_superseded).is_equal(1)
	assert_int(host.rejects.of_reason(NetRejects.Reason.TRAILING_BYTES)).is_equal(1)


func test_the_hosts_backlog_reaches_a_client_as_its_newest_message() -> void:
	var client := _connected_client()
	var counter := Counter.new(client)
	for i in 100:
		client.queue_message(1, STATE, PackedByteArray([i]))
		if i % 50 == 0:
			client.queue_message(1, EVENT, PackedByteArray([i]))
	client.poll()
	(
		assert_array(counter.events)
		. is_equal(
			[
				"packet 1:%d:0" % STATE,
				"packet 1:%d:0" % EVENT,
				"packet 1:%d:50" % STATE,
				"packet 1:%d:50" % EVENT,
				"packet 1:%d:99" % STATE,
			]
		)
	)
	assert_int(client.latest_superseded).is_equal(97)


func test_voice_and_reliable_messages_are_never_merged() -> void:
	var host := _host_with([5])
	var counter := Counter.new(host)
	for i in 3:
		host.queue_message(5, TALK, PackedByteArray([i]))
		host.queue_message(5, INTENT, PackedByteArray([i]))
	host.poll()
	assert_int(counter.events.size()).is_equal(6)
	assert_int(host.latest_superseded).is_equal(0)


func test_the_newest_rule_holds_within_one_poll_only() -> void:
	var host := _host_with([5])
	var counter := Counter.new(host)
	host.queue_message(5, POSE, PackedByteArray([1]))
	host.poll()
	host.queue_message(5, POSE, PackedByteArray([2]))
	host.poll()
	assert_array(counter.events).is_equal(["packet 5:%d:1" % POSE, "packet 5:%d:2" % POSE])
	assert_int(host.latest_superseded).is_equal(0)


func test_a_bad_packet_supersedes_nothing_and_is_still_rejected() -> void:
	var host := _host_with([5])
	var counter := Counter.new(host)
	var lane := NetKindTable.Lane.LATEST
	var trailing := NetFrame.encode(POSE, PackedByteArray([7]))
	trailing.append(0)
	# A bad packet before a good one: rejected and counted, not merged away.
	host.queue_on(5, trailing, lane)
	host.queue_message(5, POSE, PackedByteArray([1]))
	# A good one before bad ones: trailing bytes, a kind the host may not receive, a LATEST kind
	# on the reliable lane.
	host.queue_message(5, POSE, PackedByteArray([2]))
	host.queue_on(5, trailing, lane)
	host.queue_on(5, NetFrame.encode(STATE, PackedByteArray([3])), lane)
	host.queue_on(5, NetFrame.encode(POSE, PackedByteArray([4])), NetKindTable.Lane.RELIABLE)
	host.poll()
	assert_array(counter.events).is_equal(["packet 5:%d:2" % POSE])
	assert_int(host.latest_superseded).is_equal(1)
	assert_int(host.rejects.of_reason(NetRejects.Reason.TRAILING_BYTES)).is_equal(2)
	assert_int(host.rejects.of_reason(NetRejects.Reason.WRONG_DIRECTION)).is_equal(1)
	assert_int(host.rejects.of_reason(NetRejects.Reason.WRONG_LANE)).is_equal(1)


func test_a_superseded_packet_from_a_stranger_is_still_rejected() -> void:
	var host := _host_with([5])
	host.queue_message(9, POSE, PackedByteArray([1]))
	host.queue_message(9, POSE, PackedByteArray([2]))
	host.poll()
	assert_int(host.rejects.of_reason(NetRejects.Reason.UNKNOWN_PEER)).is_equal(2)
	assert_int(host.latest_superseded).is_equal(0)


func test_a_leave_and_a_join_in_between_keep_both_connections_messages() -> void:
	var host := _host_with([5, 6])
	var counter := Counter.new(host)
	# Peer ids are chosen by clients: a new client can take the id of one that just left. Another
	# peer's arrival changes nothing for peer 6.
	host.queue_message(6, POSE, PackedByteArray([10]))
	host.queue_message(5, POSE, PackedByteArray([1]))
	host.queue(NetTransport.Inbound.Type.LEFT, 5)
	host.queue(NetTransport.Inbound.Type.JOINED, 5)
	host.queue_message(5, POSE, PackedByteArray([2]))
	host.queue_message(5, POSE, PackedByteArray([3]))
	host.queue_message(6, POSE, PackedByteArray([11]))
	host.poll()
	(
		assert_array(counter.events)
		. is_equal(
			[
				"packet 5:%d:1" % POSE,
				"left 5",
				"joined 5",
				"packet 5:%d:3" % POSE,
				"packet 6:%d:11" % POSE,
			]
		)
	)


func test_a_leave_keeps_the_last_pose_of_the_connection_that_left() -> void:
	var host := _host_with([5])
	var counter := Counter.new(host)
	# The pose after the leave comes from no connected peer: it is rejected, so it must not merge
	# away the one before, the last this connection sent.
	host.queue_message(5, POSE, PackedByteArray([1]))
	host.queue(NetTransport.Inbound.Type.LEFT, 5)
	host.queue_message(5, POSE, PackedByteArray([2]))
	host.poll()
	assert_array(counter.events).is_equal(["packet 5:%d:1" % POSE, "left 5"])
	assert_int(host.rejects.of_reason(NetRejects.Reason.UNKNOWN_PEER)).is_equal(1)
	assert_int(host.latest_superseded).is_equal(0)


func test_a_state_that_overtook_the_admit_is_rejected_not_counted_as_merged() -> void:
	var client := ScriptedTransport.new(_kinds)
	client.join("somewhere", 1)
	var counter := Counter.new(client)
	# Unreliable packets can overtake the ADMIT: the one before CONNECTED is superseded by the one
	# after it, and is still rejected as from an unknown peer, not counted as merged.
	client.queue_message(1, STATE, PackedByteArray([1]))
	client.queue(NetTransport.Inbound.Type.CONNECTED, 7)
	client.queue_message(1, STATE, PackedByteArray([2]))
	client.poll()
	assert_array(counter.events).is_equal(["connected 7", "packet 1:%d:2" % STATE])
	assert_int(client.rejects.of_reason(NetRejects.Reason.UNKNOWN_PEER)).is_equal(1)
	assert_int(client.latest_superseded).is_equal(0)


func test_a_failed_join_gives_its_backends_reason() -> void:
	var client := ScriptedTransport.new(_kinds)
	client.join("somewhere", 1)
	var counter := Counter.new(client)
	var failed := NetTransport.Inbound.new(NetTransport.Inbound.Type.CONNECT_FAILED, 1)
	failed.reason = NetTransport.JOIN_NO_ROOM
	client.queued.append(failed)
	client.poll()
	assert_array(counter.events).is_equal(["no_room"])
	assert_int(client.role()).is_equal(NetTransport.Role.IDLE)


## A backend's own rejects (LaneOrder's) and the LATEST frames its hold dropped are counted in the
## inbox's order: a valid dropped frame in latest_superseded, never delivered; an invalid one as a
## reject.
func test_rejected_and_superseded_items_are_counted_in_order() -> void:
	var host := _host_with([2])
	var counter := Counter.new(host)
	var reasons: Array[NetRejects.Reason] = []
	host.packet_rejected.connect(
		func(_peer: int, reason: NetRejects.Reason) -> void: reasons.append(reason)
	)
	var rejected := NetTransport.Inbound.new(NetTransport.Inbound.Type.REJECTED, 2)
	rejected.reject = NetRejects.Reason.ORDER_HEADER_SHORT
	host.queued.append(rejected)
	var lane := NetKindTable.Lane.LATEST
	var superseded := NetTransport.Inbound.Type.SUPERSEDED
	var pose := NetFrame.encode(POSE, PackedByteArray([5]))
	host.queued.append(
		NetTransport.Inbound.new(
			superseded, 2, pose, NetKindTable.channel_of(lane), NetKindTable.mode_of(lane)
		)
	)
	host.queued.append(
		NetTransport.Inbound.new(
			superseded,
			2,
			NetFrame.encode(EVENT, PackedByteArray([1])),
			NetKindTable.channel_of(lane),
			NetKindTable.mode_of(lane)
		)
	)
	host.queue_message(2, POSE, PackedByteArray([6]))
	host.poll()
	assert_array(counter.events).is_equal(["packet 2:%d:6" % POSE])
	assert_int(host.latest_superseded).is_equal(1)
	assert_array(reasons).is_equal(
		[NetRejects.Reason.ORDER_HEADER_SHORT, NetRejects.Reason.WRONG_DIRECTION]
	)


func _connected_client() -> ScriptedTransport:
	var client := ScriptedTransport.new(_kinds)
	client.join("somewhere", 1)
	client.queue(NetTransport.Inbound.Type.CONNECTED, 7)
	client.poll()
	assert_array(Array(client.peers())).is_equal([1])
	return client


func _host_with(peer_ids: Array[int]) -> ScriptedTransport:
	var host := ScriptedTransport.new(_kinds)
	host.host(1, 8)
	for peer_id in peer_ids:
		host.queue(NetTransport.Inbound.Type.JOINED, peer_id)
	host.poll()
	return host
