class_name EnetTransport
extends NetTransport
## NetTransport over ENet. Reads ENetMultiplayerPeer directly, with no SceneMultiplayer: nothing
## parses RPC, spawn or sync commands, and nothing relays packets between clients (ARCHITECTURE §4).
## The host's own client is a LoopbackTransport (LoopbackTransport.own_client_of).
##
## A client counts as connected only when the host's ADMIT arrives. ENet completes its handshake
## before the host's code sees the peer, so a refused client would otherwise see "connected" and
## then wait for a timeout. A refusing host disconnects the peer instead of admitting it.

## ENet drops a peer that acknowledges nothing for this long; a crashed peer is noticed within
## PEER_TIMEOUT_MAX_MS. ENet runs only on the main thread, so a peer whose main thread freezes
## acknowledges nothing until it thaws. The M1 spike's 2-4 s dropped such peers (level loads,
## breakpoints), and #21 found a common freeze: on Windows a windowed D3D12 Godot process can
## freeze about 5 s (5.0 to 5.2 s) when another one on the same PC is killed or starts. Keep
## PEER_TIMEOUT_MIN_MS at 10 s or more: a "snappier drop" brings that bug back.
## tests/integration/net/enet_freeze.gd checks a 5.2 s freeze on the host and on a client, and
## enet_stall.gd that each side keeps the other through 7 s, past ENet's default of 5 s.
## Every ENet timeout is set here and nowhere else.
const PEER_TIMEOUT_LIMIT := 32
const PEER_TIMEOUT_MIN_MS := 10000
const PEER_TIMEOUT_MAX_MS := 20000
## ENet reads at most this many datagrams from its socket per service, and
## ENetMultiplayerPeer.poll() services once (#95 measured both in 4.7.2). After a freeze the
## backlog is bigger: one service took only its oldest part, and the newest arrived a poll later,
## so on the Linux CI runner the freeze check's thawed host got poses 2.4 to 3.1 s old (#95).
## poll() therefore services until one reads fewer, the socket drained, and the LATEST merge sees
## the whole backlog. tests/integration/net/enet_stall.gd checks it.
const ENET_RECEIVES_PER_SERVICE := 256
## At most this many services per poll(), so an endless stream of datagrams cannot hold a frame.
const MAX_SERVICES_PER_POLL := 16
## A join without an ADMIT gives up after this long (no host, or a full one, answers nothing).
const JOIN_TIMEOUT_MS := 5000
## The host's first packet to each client: a frame of kind 0, which no kind table allows, so it
## can never be mistaken for a game message.
const ADMIT: Array[int] = [0, 0, 0]

## The address the host listens on. "*" is every interface; 127.0.0.1 keeps local tests off the
## network (and off the firewall prompt).
var bind_address := "*"

var _peer: ENetMultiplayerPeer = null
var _join_started_ms := 0
var _client_id := 0
var _admitted := false
## Filled by the ENet signals during _peer.poll(), handled around the packets afterwards.
var _arrivals: Array[int] = []
var _departures: Array[int] = []
## The peers ENet still has. It forgets a peer during _peer.poll(), before the LEFT reaches the
## game, so a send in between must not reach ENet (it would print an engine error).
var _live: Dictionary[int, bool] = {}


func _backend_host(port: int, max_clients: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_address)
	# max_channels stays 0: 4.7.2 passes it as the host's incoming bandwidth, which throttles
	# unreliable packets to 1/32 (godotengine/godot#123963). Clients ask for the channels instead.
	var err := peer.create_server(port, max_clients)
	if err == OK:
		_use(peer)
	return err


func _backend_join(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, NetKindTable.CHANNEL_COUNT)
	if err == OK:
		_use(peer)
		# Cached: get_unique_id() errors once the connection is closed.
		_client_id = peer.get_unique_id()
		_join_started_ms = Time.get_ticks_msec()
	return err


func _backend_poll() -> void:
	if _peer == null:
		return
	_service()
	# Arrivals, then packets, then departures: the order a peer's own events happen in, so packets
	# from a peer that joined or left during this poll are not taken for strangers.
	if is_host():
		_admit_arrivals()
	while _peer.get_available_packet_count() > 0:
		# The packet's sender, channel and mode are read before get_packet() takes it.
		var from_peer := _peer.get_packet_peer()
		var channel := _peer.get_packet_channel()
		var mode := _peer.get_packet_mode()
		var bytes := _peer.get_packet()
		if not is_host() and not _admitted and _is_admit(from_peer, bytes, channel, mode):
			_admitted = true
			_push(Inbound.new(Inbound.Type.CONNECTED, _client_id))
		else:
			_push(Inbound.new(Inbound.Type.PACKET, from_peer, bytes, channel, mode))
	for peer_id in _departures:
		if is_host():
			_push(Inbound.new(Inbound.Type.LEFT, peer_id))
		elif peer_id == HOST_ID:
			_push(Inbound.new(Inbound.Type.HOST_LOST, HOST_ID))
	_arrivals.clear()
	_departures.clear()
	if not is_host():
		_check_client()


func _backend_send(to_peer: int, bytes: PackedByteArray, lane: NetKindTable.Lane) -> Error:
	if _peer == null or not _live.has(to_peer):
		return ERR_DOES_NOT_EXIST
	_peer.transfer_channel = NetKindTable.channel_of(lane)
	_peer.transfer_mode = NetKindTable.mode_of(lane)
	_peer.set_target_peer(to_peer)
	return _peer.put_packet(bytes)


func _backend_close() -> void:
	var peer := _peer
	_peer = null  # the ENet signal handlers ignore anything from now on
	_arrivals.clear()
	_departures.clear()
	_live.clear()
	_client_id = 0
	_admitted = false
	if peer != null:
		peer.close()


func _backend_disconnect(peer_id: int) -> void:
	# disconnect_later: what was already sent to the peer arrives first, as on the loopback (a
	# plain disconnect drops ENet's queue); then the client sees host_lost. Until the peer
	# acknowledges, or times out, it keeps its slot and its id.
	if _live.erase(peer_id):
		var packet_peer := _peer.get_peer(peer_id)
		if packet_peer != null:
			packet_peer.peer_disconnect_later()


## Services ENet until its socket is drained (ENET_RECEIVES_PER_SERVICE). Several services before
## any packet is taken change nothing else: ENetMultiplayerPeer queues every packet, and the ENet
## signals only fill _arrivals and _departures. A service that stops short of the limit for
## another reason leaves the rest of the socket to the next poll, as before.
func _service() -> void:
	for _i in MAX_SERVICES_PER_POLL:
		_peer.poll()
		# A client whose connection ended stops here; _check_client reports it.
		if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return
		var read := _peer.get_host().pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
		if read < ENET_RECEIVES_PER_SERVICE:
			return


func _use(peer: ENetMultiplayerPeer) -> void:
	_peer = peer
	# Bound methods, not lambdas: a lambda capturing self, held by the peer self owns, is a cycle.
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)


## Host: admits each new peer before anything else goes to it, or disconnects it. The ADMIT
## and the game's reliable messages share channel 0, so they arrive in this order.
## The client picks its own peer id (Godot only refuses 0, 1 and ids in use), so it is neither
## secret nor unique over time. A negative id would turn every send to it into "everyone but"
## (set_target_peer), and an id still leaving in this poll would be taken for the old peer.
func _admit_arrivals() -> void:
	for peer_id in _arrivals:
		if not _live.has(peer_id):  # joined and left within this poll
			continue
		if (
			is_refusing_new_connections()
			or peer_id <= HOST_ID
			or _peers.has(peer_id)
			or peer_id in _departures
		):
			_peer.disconnect_peer(peer_id)
			continue
		_set_timeout(peer_id)
		_backend_send(peer_id, PackedByteArray(ADMIT), NetKindTable.Lane.RELIABLE)
		_push(Inbound.new(Inbound.Type.JOINED, peer_id))


func _is_admit(
	from_peer: int, bytes: PackedByteArray, channel: int, mode: MultiplayerPeer.TransferMode
) -> bool:
	return (
		from_peer == HOST_ID
		and bytes == PackedByteArray(ADMIT)
		and channel == NetKindTable.channel_of(NetKindTable.Lane.RELIABLE)
		and mode == NetKindTable.mode_of(NetKindTable.Lane.RELIABLE)
	)


## The host is gone when ENet reports peer 1 disconnected (_on_peer_disconnected) or the
## connection status drops to disconnected, whichever comes first; the base class emits once.
## Before the ADMIT the same means the join failed.
func _check_client() -> void:
	var status := _peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_push(Inbound.new(Inbound.Type.HOST_LOST, HOST_ID))
	elif not _admitted and Time.get_ticks_msec() - _join_started_ms > JOIN_TIMEOUT_MS:
		_push(Inbound.new(Inbound.Type.CONNECT_FAILED, HOST_ID))


func _set_timeout(peer_id: int) -> void:
	var packet_peer := _peer.get_peer(peer_id)
	if packet_peer != null:
		packet_peer.set_timeout(PEER_TIMEOUT_LIMIT, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)


func _on_peer_connected(peer_id: int) -> void:
	if _peer == null:
		return
	if is_host():
		_live[peer_id] = true
		_arrivals.append(peer_id)
	elif peer_id == HOST_ID:
		_live[peer_id] = true
		_set_timeout(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if _peer != null:
		_live.erase(peer_id)
		_departures.append(peer_id)
