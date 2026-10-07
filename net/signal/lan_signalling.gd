class_name LanSignalling
extends RefCounted
## The signalling service served by the host itself over ws:// (ARCHITECTURE §4.8; the M6 ADR
## §2.4, E53): on the LAN, and in every headless test, so no test needs the internet. The rooms and
## the routing are SignalRouter's, the same rules the Worker (M6-5b) runs; this class only carries
## its messages over WebSockets. By default it serves no ICE servers: on one machine or a LAN, host
## candidates connect (the transcripts' replay passes theirs). The owner calls poll() every frame.

## A connection that has not finished its WebSocket handshake by then is dropped.
const HANDSHAKE_TIMEOUT_MS := 5000

## How long after its last error the service closes a socket it ends (the host left). Godot's
## WebSocketPeer drops a message that arrives in the same read as the close (#366's probe), so
## closing at once would lose the reason.
var close_grace_ms := 1000

var _server := TCPServer.new()
var _router: SignalRouter
## Socket number -> its WebSocket, from the TCP accept until it closes.
var _sockets: Dictionary[int, WebSocketPeer] = {}
## Accept time of each socket still in its handshake.
var _handshakes: Dictionary[int, int] = {}
## Sockets this side ends, and when it closes them: the router has already forgotten them, so
## their messages and their close are no events.
var _closing: Dictionary[int, int] = {}
var _next_socket := 1
var _handled := 0


## `next_code` hands out room codes (a seeded list in tests); random ones when it is empty.
func _init(ice_servers: Array = [], next_code := Callable()) -> void:
	if next_code.is_null():
		var random := RandomNumberGenerator.new()
		random.randomize()
		next_code = func() -> String: return SignalCodec.random_code(random)
	_router = SignalRouter.new(ice_servers, next_code)


## Listens on `port` (0: any free one, see port()); "*" is every address, "127.0.0.1" this
## machine only.
func listen(port_number: int, bind_address := "*") -> Error:
	return _server.listen(port_number, bind_address)


func port() -> int:
	return _server.get_local_port()


func is_listening() -> bool:
	return _server.is_listening()


## Router events handled so far: a socket opened, a message, a socket gone. Tests wait on it.
func handled() -> int:
	return _handled


func socket_count() -> int:
	return _sockets.size()


func poll() -> void:
	while _server.is_listening() and _server.is_connection_available():
		var peer := WebSocketPeer.new()
		if peer.accept_stream(_server.take_connection()) != OK:
			continue
		_sockets[_next_socket] = peer
		_handshakes[_next_socket] = Time.get_ticks_msec()
		_next_socket += 1
	for socket: int in _sockets.keys():
		if _sockets.has(socket):
			_poll_socket(socket)


func stop() -> void:
	for socket: int in _sockets.keys():
		_sockets[socket].close()
	_sockets.clear()
	_handshakes.clear()
	_closing.clear()
	_server.stop()


func _poll_socket(socket: int) -> void:
	var peer := _sockets[socket]
	peer.poll()
	match peer.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if Time.get_ticks_msec() - _handshakes[socket] > HANDSHAKE_TIMEOUT_MS:
				peer.close()
				_sockets.erase(socket)
				_handshakes.erase(socket)
		WebSocketPeer.STATE_OPEN:
			if _closing.has(socket) and Time.get_ticks_msec() >= _closing[socket]:
				peer.close()
			if _handshakes.has(socket):
				_handshakes.erase(socket)
				_router.opened(socket)
				_handled += 1
			while _sockets.has(socket) and peer.get_available_packet_count() > 0:
				var bytes := peer.get_packet()
				var text := peer.was_string_packet()
				if not _closing.has(socket):
					_handled += 1
					_deliver(_router.received(socket, bytes, text))
		WebSocketPeer.STATE_CLOSED:
			_sockets.erase(socket)
			var was_open := not _handshakes.has(socket)
			_handshakes.erase(socket)
			if _closing.has(socket):
				_closing.erase(socket)
			elif was_open:
				_handled += 1
				_deliver(_router.closed(socket))


func _deliver(out: Array[SignalRouter.Outgoing]) -> void:
	for each: SignalRouter.Outgoing in out:
		var peer: WebSocketPeer = _sockets.get(each.socket)
		# A socket its client is closing is still in a room until it reads closed; sending to it
		# would print an engine error.
		if peer == null or _closing.has(each.socket):
			continue
		if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		peer.send_text(JSON.stringify(each.message, "", false))
		if each.close:
			_closing[each.socket] = Time.get_ticks_msec() + close_grace_ms
