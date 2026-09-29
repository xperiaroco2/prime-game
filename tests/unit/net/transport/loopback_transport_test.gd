extends GdUnitTestSuite
## LoopbackTransport through a LoopbackHub, and the host's own client: the NetTransport contract
## (events, addressing, leaving, the host leaving, refusing, send errors, rejected bytes) without a
## network. EnetTransport is checked by tests/integration/net/enet_host_and_two_clients.gd.

const PORT := 7000
const EVENT := 10  # host -> client, reliable
const INTENT := 11  # client -> host, reliable
const STATE := 12  # host -> client, latest
const VOICE := 13  # both ways, voice lane
const CAP := 8
const RELIABLE := MultiplayerPeer.TRANSFER_MODE_RELIABLE

var _kinds: NetKindTable
var _hub: LoopbackHub


class Recorder:
	extends RefCounted
	var events: Array[String] = []
	## "from:kind:payload hex" per received message.
	var packets: Array[String] = []

	func _init(transport: NetTransport) -> void:
		transport.connected.connect(_on_connected)
		transport.connect_failed.connect(_on_connect_failed)
		transport.peer_joined.connect(_on_peer_joined)
		transport.peer_left.connect(_on_peer_left)
		transport.host_lost.connect(_on_host_lost)
		transport.packet_received.connect(_on_packet_received)

	func _on_connected(own_id: int) -> void:
		events.append("connected %d" % own_id)

	func _on_connect_failed() -> void:
		events.append("connect_failed")

	func _on_peer_joined(peer_id: int) -> void:
		events.append("joined %d" % peer_id)

	func _on_peer_left(peer_id: int) -> void:
		events.append("left %d" % peer_id)

	func _on_host_lost() -> void:
		events.append("host_lost")

	func _on_packet_received(from_peer: int, kind: int, payload: PackedByteArray) -> void:
		packets.append("%d:%d:%s" % [from_peer, kind, payload.hex_encode()])


func before_test() -> void:
	_kinds = NetKindTable.new()
	_kinds.add(EVENT, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.HOST_TO_CLIENT, CAP)
	_kinds.add(INTENT, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.CLIENT_TO_HOST, CAP)
	_kinds.add(STATE, NetKindTable.Lane.LATEST, NetKindTable.Direction.HOST_TO_CLIENT, CAP)
	_kinds.add(VOICE, NetKindTable.Lane.VOICE, NetKindTable.Direction.BOTH, CAP)
	_hub = LoopbackHub.new()


func test_own_client_is_peer_one_on_both_sides() -> void:
	var host := _host()
	var own := LoopbackTransport.own_client_of(host)
	var host_rec := Recorder.new(host)
	var own_rec := Recorder.new(own)
	_poll([host, own])
	assert_array(host_rec.events).is_equal(["joined 1"])
	assert_array(own_rec.events).is_equal(["connected 1"])
	assert_array(Array(host.peers())).is_equal([1])
	assert_array(Array(own.peers())).is_equal([1])
	assert_int(own.own_id()).is_equal(NetTransport.HOST_ID)
	assert_bool(host.is_host()).is_true()
	assert_bool(own.is_host()).is_false()


func test_own_client_once_and_only_for_a_host() -> void:
	var host := _host()
	assert_object(LoopbackTransport.own_client_of(host)).is_not_null()
	assert_object(LoopbackTransport.own_client_of(host)).is_null()
	assert_object(LoopbackTransport.own_client_of(LoopbackTransport.new(_kinds, _hub))).is_null()


func test_clients_join_with_their_own_ids() -> void:
	var host := _host()
	var host_rec := Recorder.new(host)
	var a := _client()
	var b := _client()
	var a_rec := Recorder.new(a)
	var b_rec := Recorder.new(b)
	_poll([host, a, b])
	assert_array(host_rec.events).is_equal(["joined 2", "joined 3"])
	assert_array(a_rec.events).is_equal(["connected 2"])
	assert_array(b_rec.events).is_equal(["connected 3"])
	assert_array(Array(host.peers())).is_equal([2, 3])
	assert_array(Array(a.peers())).is_equal([1])
	assert_int(b.own_id()).is_equal(3)


func test_messages_travel_both_ways() -> void:
	var host := _host()
	var own := LoopbackTransport.own_client_of(host)
	var client := _client()
	_poll([host, own, client])
	var host_rec := Recorder.new(host)
	var own_rec := Recorder.new(own)
	var client_rec := Recorder.new(client)
	assert_int(client.send(1, INTENT, PackedByteArray([0xAA]))).is_equal(OK)
	assert_int(own.send(1, VOICE, PackedByteArray([0xBB]))).is_equal(OK)
	assert_int(host.send(2, EVENT, PackedByteArray([0xCC]))).is_equal(OK)
	assert_int(host.send(1, STATE, PackedByteArray([0xDD]))).is_equal(OK)
	_poll([host, own, client])
	assert_array(host_rec.packets).is_equal(["2:%d:aa" % INTENT, "1:%d:bb" % VOICE])
	assert_array(client_rec.packets).is_equal(["1:%d:cc" % EVENT])
	assert_array(own_rec.packets).is_equal(["1:%d:dd" % STATE])


func test_a_message_reaches_only_its_peer() -> void:
	var host := _host()
	var own := LoopbackTransport.own_client_of(host)
	var a := _client()
	var b := _client()
	_poll([host, own, a, b])
	var own_rec := Recorder.new(own)
	var a_rec := Recorder.new(a)
	var b_rec := Recorder.new(b)
	host.send(3, EVENT, PackedByteArray([3]))
	_poll([host, own, a, b])
	assert_array(b_rec.packets).is_equal(["1:%d:03" % EVENT])
	assert_array(a_rec.packets).is_empty()
	assert_array(own_rec.packets).is_empty()


func test_own_and_remote_clients_get_the_same_messages_in_the_same_order() -> void:
	var host := _host()
	var own := LoopbackTransport.own_client_of(host)
	var remote := _client()
	_poll([host, own, remote])
	var own_rec := Recorder.new(own)
	var remote_rec := Recorder.new(remote)
	for kind: int in [EVENT, STATE, VOICE]:
		for peer_id: int in [1, 2]:
			host.send(peer_id, kind, PackedByteArray([kind, 0, 255]))
	host.send(1, EVENT, PackedByteArray())
	host.send(2, EVENT, PackedByteArray())
	_poll([host, own, remote])
	assert_int(own_rec.packets.size()).is_equal(4)
	assert_array(own_rec.packets).is_equal(remote_rec.packets)


func test_messages_wait_for_the_receiver_to_poll() -> void:
	var host := _host()
	var client := _client()
	_poll([host, client])
	var client_rec := Recorder.new(client)
	host.send(2, EVENT, PackedByteArray([1]))
	host.poll()
	assert_array(client_rec.packets).is_empty()
	client.poll()
	assert_int(client_rec.packets.size()).is_equal(1)


func test_a_client_leaving() -> void:
	var host := _host()
	var a := _client()
	var b := _client()
	_poll([host, a, b])
	var host_rec := Recorder.new(host)
	var a_rec := Recorder.new(a)
	var b_rec := Recorder.new(b)
	a.close()
	_poll([host, a, b])
	assert_array(host_rec.events).is_equal(["left 2"])
	assert_array(a_rec.events).is_empty()
	assert_array(b_rec.events).is_empty()
	assert_array(Array(host.peers())).is_equal([3])
	assert_int(host.send(2, EVENT, PackedByteArray())).is_equal(ERR_DOES_NOT_EXIST)
	assert_int(a.role()).is_equal(NetTransport.Role.IDLE)


func test_the_host_closing_ends_the_match_for_every_client() -> void:
	var host := _host()
	var own := LoopbackTransport.own_client_of(host)
	var client := _client()
	_poll([host, own, client])
	var own_rec := Recorder.new(own)
	var client_rec := Recorder.new(client)
	host.close()
	_poll([host, own, client])
	assert_array(own_rec.events).is_equal(["host_lost"])
	assert_array(client_rec.events).is_equal(["host_lost"])
	assert_int(client.role()).is_equal(NetTransport.Role.IDLE)
	assert_int(client.own_id()).is_equal(0)
	assert_int(client.send(1, INTENT, PackedByteArray())).is_equal(ERR_DOES_NOT_EXIST)
	assert_object(_hub.host_at(PORT)).is_null()


func test_a_host_dropped_without_close_is_lost_too() -> void:
	var host := _host()
	var client := _client()
	_poll([host, client])
	var client_rec := Recorder.new(client)
	host = null
	client.poll()
	assert_array(client_rec.events).is_equal(["host_lost"])


func test_a_client_can_join_again_after_losing_the_host() -> void:
	var host := _host()
	var client := _client()
	_poll([host, client])
	host.close()
	client.poll()
	var again := _host()
	var client_rec := Recorder.new(client)
	assert_int(client.join("loopback", PORT)).is_equal(OK)
	_poll([again, client])
	assert_array(client_rec.events).is_equal(["connected 3"])


func test_a_refusing_host_turns_joins_away() -> void:
	var host := _host()
	host.set_refuse_new_connections(true)
	var host_rec := Recorder.new(host)
	var client := _client()
	var client_rec := Recorder.new(client)
	var own := LoopbackTransport.own_client_of(host)
	_poll([host, client, own])
	assert_array(client_rec.events).is_equal(["connect_failed"])
	# The host's own client is its player, not a new connection.
	assert_array(host_rec.events).is_equal(["joined 1"])
	assert_int(client.role()).is_equal(NetTransport.Role.IDLE)
	host.set_refuse_new_connections(false)
	var late := _client()
	var late_rec := Recorder.new(late)
	_poll([host, late])
	assert_array(late_rec.events).is_equal(["connected 2"])


func test_a_full_host_turns_joins_away() -> void:
	var host := LoopbackTransport.new(_kinds, _hub)
	assert_int(host.host(PORT, 1)).is_equal(OK)
	LoopbackTransport.own_client_of(host)  # not counted: max_clients counts remote clients
	var first := _client()
	var second := _client()
	var first_rec := Recorder.new(first)
	var second_rec := Recorder.new(second)
	_poll([host, first, second])
	assert_array(first_rec.events).is_equal(["connected 2"])
	assert_array(second_rec.events).is_equal(["connect_failed"])


func test_joining_where_nobody_hosts_fails() -> void:
	var client := _client()
	var client_rec := Recorder.new(client)
	client.poll()
	assert_array(client_rec.events).is_equal(["connect_failed"])


func test_hosting_and_joining_need_an_idle_transport_and_a_hub() -> void:
	var host := _host()
	assert_int(host.host(PORT + 1, 8)).is_equal(ERR_ALREADY_IN_USE)
	assert_int(host.join("loopback", PORT)).is_equal(ERR_ALREADY_IN_USE)
	assert_int(LoopbackTransport.new(_kinds, _hub).host(PORT, 8)).is_equal(ERR_ALREADY_IN_USE)
	assert_int(LoopbackTransport.new(_kinds).host(PORT, 8)).is_equal(ERR_UNCONFIGURED)
	assert_int(LoopbackTransport.new(_kinds).join("loopback", PORT)).is_equal(ERR_UNCONFIGURED)


func test_send_refuses_what_the_table_forbids() -> void:
	var host := _host()
	var client := _client()
	assert_int(client.send(1, INTENT, PackedByteArray())).is_equal(ERR_DOES_NOT_EXIST)
	_poll([host, client])
	var too_big := PackedByteArray()
	too_big.resize(CAP + 1)
	assert_int(client.send(1, EVENT, PackedByteArray())).is_equal(ERR_INVALID_PARAMETER)
	assert_int(client.send(1, 99, PackedByteArray())).is_equal(ERR_INVALID_PARAMETER)
	assert_int(client.send(1, INTENT, too_big)).is_equal(ERR_INVALID_PARAMETER)
	assert_int(client.send(3, INTENT, PackedByteArray())).is_equal(ERR_DOES_NOT_EXIST)
	assert_int(host.send(2, INTENT, PackedByteArray())).is_equal(ERR_INVALID_PARAMETER)
	assert_int(host.send(2, EVENT, too_big)).is_equal(ERR_INVALID_PARAMETER)
	assert_int(host.send(42, EVENT, PackedByteArray())).is_equal(ERR_DOES_NOT_EXIST)
	assert_int(host.send(2, EVENT, PackedByteArray())).is_equal(OK)


func test_bad_bytes_are_counted_and_never_delivered() -> void:
	var host := _host()
	var client := _client()
	_poll([host, client])
	var host_rec := Recorder.new(host)
	var trailing := NetFrame.encode(INTENT, PackedByteArray([1]))
	trailing.append(0)
	host.receive_bytes(2, trailing, 0, RELIABLE)
	host.receive_bytes(2, NetFrame.encode(EVENT, PackedByteArray()), 0, RELIABLE)
	host.receive_bytes(2, NetFrame.encode(VOICE, PackedByteArray()), 0, RELIABLE)
	host.receive_bytes(42, NetFrame.encode(INTENT, PackedByteArray()), 0, RELIABLE)
	host.receive_bytes(2, PackedByteArray([INTENT]), 0, RELIABLE)
	assert_array(host_rec.packets).is_empty()
	assert_int(host.rejects.total()).is_equal(5)
	assert_int(host.rejects.of_reason(NetRejects.Reason.TRAILING_BYTES)).is_equal(1)
	assert_int(host.rejects.of_reason(NetRejects.Reason.WRONG_DIRECTION)).is_equal(1)
	assert_int(host.rejects.of_reason(NetRejects.Reason.WRONG_LANE)).is_equal(1)
	assert_int(host.rejects.of_reason(NetRejects.Reason.UNKNOWN_PEER)).is_equal(1)
	assert_int(host.rejects.of_reason(NetRejects.Reason.TOO_SHORT)).is_equal(1)
	assert_int(host.rejects.from_peer(2)).is_equal(4)


func test_a_client_accepts_only_the_host() -> void:
	var host := _host()
	var client := _client()
	_poll([host, client])
	var client_rec := Recorder.new(client)
	client.receive_bytes(3, NetFrame.encode(EVENT, PackedByteArray()), 0, RELIABLE)
	assert_array(client_rec.packets).is_empty()
	assert_int(client.rejects.of_reason(NetRejects.Reason.UNKNOWN_PEER)).is_equal(1)


func _host() -> LoopbackTransport:
	var host := LoopbackTransport.new(_kinds, _hub)
	assert_int(host.host(PORT, 8)).is_equal(OK)
	return host


func _client() -> LoopbackTransport:
	var client := LoopbackTransport.new(_kinds, _hub)
	assert_int(client.join("loopback", PORT)).is_equal(OK)
	return client


## Polls every transport a few rounds, so replies to replies arrive too.
func _poll(transports: Array[LoopbackTransport]) -> void:
	for _i in 3:
		for transport: LoopbackTransport in transports:
			transport.poll()
