class_name SpikeEnetTransport
extends SpikeTransport
## Spike (#13): SpikeTransport over Godot's high-level multiplayer (SceneMultiplayer) on ENet.
## Raw bytes through send_bytes and peer_packet; no RPCs, so no node paths leak into the protocol.
## Server relay is off: a client can reach only the host, never another client.

# ENet's default peer timeout is up to 30 s; a killed process should drop within a few seconds.
const TIMEOUT_LIMIT := 8
const TIMEOUT_MIN_MS := 2000
const TIMEOUT_MAX_MS := 4000
const CHANNELS := 2

var _mp := SceneMultiplayer.new()
var _peer: ENetMultiplayerPeer
# Cached: ENetMultiplayerPeer.get_unique_id() errors once the connection is gone.
var _own_id := 0


func _init() -> void:
	# A SceneMultiplayer outside the SceneTree drops every packet until it has a root path, even raw
	# bytes that never touch a node ("Multiplayer root was not initialized").
	_mp.root_path = ^"/root"
	_mp.server_relay = false
	_mp.peer_connected.connect(_on_peer_connected)
	_mp.peer_disconnected.connect(func(id: int) -> void: peer_left.emit(id))
	_mp.connected_to_server.connect(_on_connected_to_server)
	_mp.connection_failed.connect(func() -> void: connect_failed.emit())
	_mp.server_disconnected.connect(_on_server_disconnected)
	_mp.peer_packet.connect(
		func(id: int, bytes: PackedByteArray) -> void: packet_received.emit(id, bytes)
	)


func host(bind_ip: String, port: int, max_clients: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	_peer.set_bind_ip(bind_ip)
	var err := _peer.create_server(port, max_clients, CHANNELS)
	if err == OK:
		_mp.multiplayer_peer = _peer
		_own_id = HOST_ID
	return err


func join(address: String, port: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port, CHANNELS)
	if err == OK:
		_mp.multiplayer_peer = _peer
	return err


func poll() -> void:
	if _peer != null:
		_mp.poll()


func send(to_peer: int, bytes: PackedByteArray, reliable: bool) -> Error:
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var mode := (
		MultiplayerPeer.TRANSFER_MODE_RELIABLE
		if reliable
		else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	)
	# Channel 0 reliable, channel 1 unreliable, so a lost unreliable packet never stalls the other.
	return _mp.send_bytes(bytes, to_peer, mode, 0 if reliable else 1)


func own_id() -> int:
	return _own_id


func close() -> void:
	_own_id = 0
	if _peer != null:
		_peer.close()
		_peer = null


func _on_connected_to_server() -> void:
	_own_id = _mp.get_unique_id()
	connected.emit(_own_id)


func _on_server_disconnected() -> void:
	_own_id = 0
	disconnected.emit()


func _on_peer_connected(id: int) -> void:
	var packet_peer := _peer.get_peer(id)
	if packet_peer != null:
		packet_peer.set_timeout(TIMEOUT_LIMIT, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)
	peer_joined.emit(id)
