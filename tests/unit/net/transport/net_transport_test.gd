extends GdUnitTestSuite
## NetTransport's inbox with a scripted backend: the order and the once-only rules of its signals,
## whatever the backend pushes (ENet can push HOST_LOST twice in one poll).

const EVENT := 10
const INTENT := 11
const RELIABLE := MultiplayerPeer.TRANSFER_MODE_RELIABLE
const HOST_LOST := NetTransport.Inbound.Type.HOST_LOST

var _kinds: NetKindTable


## A backend that pushes whatever the test queued, on the next poll.
class ScriptedTransport:
	extends NetTransport
	var queued: Array[NetTransport.Inbound] = []

	func queue(
		item_type: NetTransport.Inbound.Type, peer_id: int, bytes := PackedByteArray()
	) -> void:
		queued.append(NetTransport.Inbound.new(item_type, peer_id, bytes))

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
		transport.connect_failed.connect(func() -> void: events.append("connect_failed"))
		transport.peer_joined.connect(
			func(peer_id: int) -> void: events.append("joined %d" % peer_id)
		)
		transport.peer_left.connect(func(peer_id: int) -> void: events.append("left %d" % peer_id))
		transport.host_lost.connect(func() -> void: events.append("host_lost"))
		transport.packet_received.connect(
			func(from_peer: int, kind: int, _payload: PackedByteArray) -> void:
				events.append("packet %d:%d" % [from_peer, kind])
		)


func before_test() -> void:
	_kinds = NetKindTable.new()
	_kinds.add(EVENT, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.HOST_TO_CLIENT, 8)
	_kinds.add(INTENT, NetKindTable.Lane.RELIABLE, NetKindTable.Direction.CLIENT_TO_HOST, 8)


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


func _connected_client() -> ScriptedTransport:
	var client := ScriptedTransport.new(_kinds)
	client.join("somewhere", 1)
	client.queue(NetTransport.Inbound.Type.CONNECTED, 7)
	client.poll()
	assert_array(Array(client.peers())).is_equal([1])
	return client
