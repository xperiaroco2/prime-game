class_name SpikeEnetTransport
extends SpikeTransport
## Spike (#13): SpikeTransport over Godot's high-level multiplayer (SceneMultiplayer) on ENet.
## Raw bytes through send_bytes and peer_packet; we send no RPCs. SceneMultiplayer still parses
## incoming RPC, spawn and sync commands: any @rpc method under /root would become callable by
## clients. The real net/ should read packets from ENetMultiplayerPeer directly instead.
## Server relay is off: a client can reach only the host, never another client.

# ENet's default peer timeout is up to 30 s; a killed process should drop within a few seconds.
const TIMEOUT_LIMIT := 8
const TIMEOUT_MIN_MS := 2000
const TIMEOUT_MAX_MS := 4000

var _mp := SceneMultiplayer.new()
var _peer: ENetMultiplayerPeer
# Cached: ENetMultiplayerPeer.get_unique_id() errors once the connection is gone.
var _own_id := 0


func _init() -> void:
	# A SceneMultiplayer outside the SceneTree drops every packet until it has a root path, even raw
	# bytes that never touch a node ("Multiplayer root was not initialized").
	_mp.root_path = ^"/root"
	_mp.server_relay = false
	# Bound methods, not lambdas: a lambda capturing self, held by _mp, which self owns, is a cycle.
	_mp.peer_connected.connect(_on_peer_connected)
	_mp.peer_disconnected.connect(_on_peer_disconnected)
	_mp.connected_to_server.connect(_on_connected_to_server)
	_mp.connection_failed.connect(_on_connection_failed)
	_mp.server_disconnected.connect(_on_server_disconnected)
	_mp.peer_packet.connect(_on_peer_packet)


func host(bind_ip: String, port: int, max_clients: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	_peer.set_bind_ip(bind_ip)
	# max_channels stays 0 (ENet's maximum): Godot 4.7.2's create_server passes it on as the host's
	# *incoming bandwidth* (create_host_bound(ip, port, peers, 0, max_channels, out_bandwidth)), so
	# 1 announced 3 bytes/s (1 + SYSCH_MAX 2) and every client throttled its unreliable packets to
	# as little as 1/32 (#15; godotengine/godot#123963). The
	# client asks for the channels it needs in join().
	var err := _peer.create_server(port, max_clients)
	if err == OK:
		_mp.multiplayer_peer = _peer
		_own_id = HOST_ID
	return err


func join(address: String, port: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	# Channels beyond ENet's system ones: SceneMultiplayer channel n > 0 is ENet channel
	# SYSCH_MAX + n - 1, so CHANNELS - 1 extra channels carry channels 1.. .
	var err := _peer.create_client(address, port, CHANNELS - 1)
	if err == OK:
		_mp.multiplayer_peer = _peer
	return err


func poll() -> void:
	if _peer != null:
		_mp.poll()


func send(
	to_peer: int, bytes: PackedByteArray, reliable: bool, channel: int = CHANNEL_GAME
) -> Error:
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	# ENetMultiplayerPeer does not check the channel against the channels set up in join(); a
	# send on a missing channel would fail or vanish inside ENet instead of here.
	if channel < 0 or channel >= CHANNELS:
		return ERR_INVALID_PARAMETER
	# Channel 0 keeps each transfer mode apart: lost unreliable packets never stall reliable ones.
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
	if not reliable:
		mode = (
			MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
			if channel == CHANNEL_VOICE
			else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
		)
	return _mp.send_bytes(bytes, to_peer, mode, channel)


func pop_sent_bytes() -> int:
	if _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return -1
	return int(_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))


func own_id() -> int:
	return _own_id


func close() -> void:
	_own_id = 0
	if _peer != null:
		_peer.close()
		_peer = null


## Each ENet peer's round trip, loss and throttle, without resetting any counter.
func peers_line() -> String:
	if _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return "none"
	var parts := PackedStringArray()
	for p in _peer.host.get_peers():
		(
			parts
			. append(
				(
					"rtt=%.0f last_rtt=%.0f last_var=%.0f loss=%.0f throttle=%.0f/%.0f acc=%.0f dec=%.0f"
					% [
						p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
						p.get_statistic(ENetPacketPeer.PEER_LAST_ROUND_TRIP_TIME),
						p.get_statistic(ENetPacketPeer.PEER_LAST_ROUND_TRIP_TIME_VARIANCE),
						p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS),
						p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE),
						p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT),
						p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_ACCELERATION),
						p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_DECELERATION),
					]
				)
			)
		)
	return ", ".join(parts)


## Each ENet peer's throttle and throttle limit, for logging every change.
func throttle_line() -> String:
	if _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return "none"
	var parts := PackedStringArray()
	for p in _peer.host.get_peers():
		(
			parts
			. append(
				(
					"%.0f/%.0f"
					% [
						p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE),
						p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT),
					]
				)
			)
		)
	return ",".join(parts)


## Temporary diagnostics: host packet counters since the last call, and each ENet peer's state.
func debug_line() -> String:
	# The host getter errors once the peer is closed, so check the status first.
	if _peer == null or _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return "no host"
	var conn := _peer.host
	var parts := PackedStringArray(
		[
			(
				"sentB=%d sent=%d recv=%d"
				% [
					conn.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA),
					conn.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS),
					conn.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS),
				]
			)
		]
	)
	for p in conn.get_peers():
		(
			parts
			. append(
				(
					"[port=%d state=%d rtt=%.0f loss=%.0f throttle=%.0f]"
					% [
						p.get_remote_port(),
						p.get_state(),
						p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
						p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS),
						p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE),
					]
				)
			)
		)
	return " ".join(parts)


func _on_peer_connected(id: int) -> void:
	var packet_peer := _peer.get_peer(id)
	if packet_peer != null:
		packet_peer.set_timeout(TIMEOUT_LIMIT, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	peer_left.emit(id)


func _on_connected_to_server() -> void:
	_own_id = _mp.get_unique_id()
	connected.emit(_own_id)


func _on_connection_failed() -> void:
	connect_failed.emit()


func _on_server_disconnected() -> void:
	_own_id = 0
	disconnected.emit()


func _on_peer_packet(id: int, bytes: PackedByteArray) -> void:
	packet_received.emit(id, bytes)
