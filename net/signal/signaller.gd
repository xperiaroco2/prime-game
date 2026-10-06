class_name Signaller
extends RefCounted
## The client side of the signalling protocol (ARCHITECTURE §4.8; the M6 ADR §2.4), over a
## WebSocket: wss:// to the Worker (M6-5b), ws:// to a LanSignalling. A host opens a room and
## trades offers and candidates with each joiner it hears of; a joiner joins a code and answers.
## Every message received is checked by SignalCodec for this side; one that fails is dropped and
## counted in `rejected`, never acted on. Signals fire only from poll(), which the owner calls every
## frame. Messages sent before the socket opens wait and go out in order when it does.

signal opened
## The socket closed, or never opened (after a connect_to() that returned OK). After it this
## Signaller is done.
signal closed
## Host: the service made the room.
signal room_opened(code: String, ice_servers: Array)
## Host: joiner `joiner` (the service's number for it in this room) wants in.
signal joiner_arrived(joiner: int)
signal answer_received(joiner: int, sdp: String)
## Host: from joiner `joiner`. Joiner: from the host, and `joiner` is 0.
signal candidate_received(joiner: int, mid: String, index: int, cand: String)
## Joiner: the room exists, with the host's protocol and content hash (an s64, as
## ContentFingerprint gives it); advisory only (the host decides with Hello, the ADR §2.5).
signal room_found(protocol: int, content: int)
signal offer_received(id: int, sdp: String, ice_servers: Array)
## The service refused something: `why` is printable text, normally one of SignalCodec's WHY_
## reasons (a newer service may send another). The service forwards every offer and answer: the
## host takes one answer per offer and the joiner one offer per attempt (the ADR §2.3).
signal refused(why: String)

enum Role { NONE, HOST, JOINER }

## A socket still connecting this long after connect_to() is given up, and closed fires (a
## placeholder, not a decision). On Windows a refused TCP connect stays connecting for 20 s and more
## (Godot 4.7.2, #431), so without it a joiner whose service is down waited for its join timeout
## and failed as host_unreachable instead of service_unreachable.
const CONNECT_TIMEOUT_MS := 5000

## Received messages dropped as malformed or not meant for this side.
var rejected := 0
## CONNECT_TIMEOUT_MS; tests shorten it.
var connect_timeout_ms := CONNECT_TIMEOUT_MS

var _socket := WebSocketPeer.new()
var _role := Role.NONE
var _queue := PackedStringArray()
var _started := false
var _open := false
var _done := false
var _started_ms := 0


func connect_to(url: String) -> Error:
	var error := _socket.connect_to_url(url)
	_started = error == OK
	_started_ms = Time.get_ticks_msec()
	return error


func is_open() -> bool:
	return _open and not _done


func close() -> void:
	_socket.close()


func poll() -> void:
	if not _started or _done:
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _open:
		_open = true
		for text: String in _queue:
			_socket.send_text(text)
		_queue.clear()
		opened.emit()
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		if not _socket.was_string_packet():
			rejected += 1
			continue
		_handle(bytes)
	var stuck := (
		state == WebSocketPeer.STATE_CONNECTING
		and Time.get_ticks_msec() - _started_ms > connect_timeout_ms
	)
	if stuck:
		_socket.close()
	if state == WebSocketPeer.STATE_CLOSED or stuck:
		_done = true
		closed.emit()


## Host: asks for a room for at most `max_joiners` joiners at once; `content` is the content hash.
func open_room(protocol: int, content: int, max_joiners: int) -> bool:
	_role = Role.HOST
	var fields := {
		"protocol": protocol, "content": SignalCodec.content_text(content), "max": max_joiners
	}
	return _send(SignalCodec.Side.UNSET, "open", fields)


func send_offer(joiner: int, id: int, sdp: String) -> bool:
	return _send(SignalCodec.Side.HOST, "offer", {"to": joiner, "id": id, "sdp": sdp})


func send_candidate_to(joiner: int, mid: String, index: int, cand: String) -> bool:
	var fields := {"to": joiner, "mid": mid, "index": index, "cand": cand}
	return _send(SignalCodec.Side.HOST, "candidate", fields)


## Host: refuse joins (entering Loading) / allow them again (back in the Lobby).
func close_room() -> bool:
	return _send(SignalCodec.Side.HOST, "close", {})


func reopen_room() -> bool:
	return _send(SignalCodec.Side.HOST, "reopen", {})


## Joiner: `code` as SignalCodec.is_code accepts it (the caller normalizes what was typed).
func join_room(code: String) -> bool:
	_role = Role.JOINER
	return _send(SignalCodec.Side.UNSET, "join", {"code": code})


func send_answer(sdp: String) -> bool:
	return _send(SignalCodec.Side.JOINER, "answer", {"sdp": sdp})


func send_candidate(mid: String, index: int, cand: String) -> bool:
	return _send(SignalCodec.Side.JOINER, "candidate", {"mid": mid, "index": index, "cand": cand})


func _send(side: int, type: String, fields: Dictionary) -> bool:
	var text := SignalCodec.encode(side, type, fields)
	if text == "" or _done:
		return false
	if not _open:
		_queue.append(text)
		return true
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return _socket.send_text(text) == OK


func _handle(bytes: PackedByteArray) -> void:
	var side := SignalCodec.Side.TO_HOST if _role == Role.HOST else SignalCodec.Side.TO_JOINER
	if _role == Role.NONE:
		rejected += 1
		return
	var decoded := SignalCodec.decode(bytes, side)
	if not decoded.ok():
		rejected += 1
		return
	var fields := decoded.fields
	match decoded.type:
		"room":
			room_opened.emit(fields["code"], fields["ice_servers"])
		"join":
			joiner_arrived.emit(fields["from"])
		"answer":
			answer_received.emit(fields["from"], fields["sdp"])
		"candidate":
			var joiner: int = fields.get("from", 0)
			candidate_received.emit(joiner, fields["mid"], fields["index"], fields["cand"])
		"found":
			room_found.emit(fields["protocol"], SignalCodec.content_hash(str(fields["content"])))
		"offer":
			offer_received.emit(fields["id"], fields["sdp"], fields["ice_servers"])
		"error":
			refused.emit(fields["why"])
