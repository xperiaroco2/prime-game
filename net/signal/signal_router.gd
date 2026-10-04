class_name SignalRouter
extends RefCounted
## The signalling service's rooms and routing (ARCHITECTURE §4.8), with no sockets: the owner
## numbers its sockets, reports opened(), received() and closed(), and sends what each returns.
## LanSignalling runs it over WebSockets; the Worker (M6-5b) has the same rules in JavaScript, and
## both replay the transcripts in tests/fixtures/signal/.
##
## A socket's first accepted message fixes its role: "open" makes it a room's host, "join" a
## joiner. A joiner's messages go only to its room's host, whatever they name; the host's go only
## to a joiner of its own room named in "to"; joiners never see each other. Every message sent on
## is rebuilt from its checked fields (SignalCodec), so nothing a sender adds passes through.
## There is no reclaim: the host's socket closing closes the room and its joiners' sockets.

enum Role { NONE, HOST, JOINER }

## Placeholders, "not a decision" (the ADR §2.4): forwarded candidates per joiner, each way.
const MAX_CANDIDATES := 32
## Attempts at a code no open room holds, before the service answers WHY_BUSY.
const CODE_ATTEMPTS := 16


## One message for one socket, and whether the service closes that socket after it.
class Outgoing:
	extends RefCounted
	var socket := 0
	var message: Dictionary = {}
	var close := false

	func _init(to_socket: int, sent: Dictionary, close_after: bool) -> void:
		socket = to_socket
		message = sent
		close = close_after


class Peer:
	extends RefCounted
	var role := Role.NONE
	var code := ""
	## The joiner's number in its room ("from" and "to"), 1 upward, never reused in that room.
	var number := 0
	var candidates_up := 0
	var candidates_down := 0


class Room:
	extends RefCounted
	var host := 0
	var protocol := 0
	var content := ""
	var max_joiners := 0
	var closed := false
	var next_number := 1
	## Joiner number -> socket.
	var joiners: Dictionary[int, int] = {}


var _ice_servers: Array = []
var _next_code: Callable
var _peers: Dictionary[int, Peer] = {}
var _rooms: Dictionary[String, Room] = {}


## `ice_servers`: what "room" and every "offer" carry (STUN from the configuration, E58); an empty
## list on the LAN. `next_code`: returns a candidate code, SignalCodec.random_code in service, a
## fixed list in the transcripts.
func _init(ice_servers: Array, next_code: Callable) -> void:
	_ice_servers = ice_servers.duplicate(true)
	_next_code = next_code


func opened(socket: int) -> void:
	_peers[socket] = Peer.new()


func room_count() -> int:
	return _rooms.size()


## What the service sends for a text (`text` true) or binary message from `socket`.
func received(socket: int, bytes: PackedByteArray, text := true) -> Array[Outgoing]:
	var out: Array[Outgoing] = []
	var peer: Peer = _peers.get(socket)
	if peer == null:
		return out
	var side: int = SignalCodec.Side.UNSET
	if peer.role == Role.HOST:
		side = SignalCodec.Side.HOST
	elif peer.role == Role.JOINER:
		side = SignalCodec.Side.JOINER
	var decoded := SignalCodec.decode(bytes, side)
	if not text:
		decoded.why = SignalCodec.WHY_BAD
	if not decoded.ok():
		out.append(_error(socket, decoded.why))
		return out
	match peer.role:
		Role.NONE:
			if decoded.type == "open":
				_open(socket, peer, decoded.fields, out)
			else:
				_join(socket, peer, decoded.fields, out)
		Role.HOST:
			_from_host(socket, peer, decoded, out)
		Role.JOINER:
			_from_joiner(peer, decoded, out)
	return out


## What the service sends when `socket` went away. Idempotent.
func closed(socket: int) -> Array[Outgoing]:
	var out: Array[Outgoing] = []
	var peer: Peer = _peers.get(socket)
	_peers.erase(socket)
	if peer == null or not _rooms.has(peer.code):
		return out
	var room := _rooms[peer.code]
	if peer.role == Role.JOINER:
		room.joiners.erase(peer.number)
	elif peer.role == Role.HOST:
		_rooms.erase(peer.code)
		for number: int in room.joiners:
			var joiner := room.joiners[number]
			_peers.erase(joiner)
			out.append(_error(joiner, SignalCodec.WHY_HOST_LEFT, true))
	return out


func _open(socket: int, peer: Peer, fields: Dictionary, out: Array[Outgoing]) -> void:
	var code := ""
	for attempt: int in CODE_ATTEMPTS:
		var candidate: String = _next_code.call()
		if SignalCodec.is_code(candidate) and not _rooms.has(candidate):
			code = candidate
			break
	if code == "":
		out.append(_error(socket, SignalCodec.WHY_BUSY))
		return
	var room := Room.new()
	room.host = socket
	room.protocol = fields["protocol"]
	room.content = fields["content"]
	room.max_joiners = fields["max"]
	_rooms[code] = room
	peer.role = Role.HOST
	peer.code = code
	out.append(_send(socket, "room", {"code": code, "ice_servers": _ice_servers.duplicate(true)}))


func _join(socket: int, peer: Peer, fields: Dictionary, out: Array[Outgoing]) -> void:
	var code: String = fields["code"]
	var room: Room = _rooms.get(code)
	if room == null:
		out.append(_error(socket, SignalCodec.WHY_NO_ROOM))
		return
	if room.closed:
		out.append(_error(socket, SignalCodec.WHY_STARTED))
		return
	if room.joiners.size() >= room.max_joiners:
		out.append(_error(socket, SignalCodec.WHY_FULL))
		return
	peer.role = Role.JOINER
	peer.code = code
	peer.number = room.next_number
	room.next_number += 1
	room.joiners[peer.number] = socket
	out.append(_send(socket, "found", {"protocol": room.protocol, "content": room.content}))
	out.append(_send(room.host, "join", {"from": peer.number}))


func _from_host(
	socket: int, peer: Peer, decoded: SignalCodec.Decoded, out: Array[Outgoing]
) -> void:
	var room := _rooms[peer.code]
	var fields := decoded.fields
	match decoded.type:
		"close":
			room.closed = true
			return
		"reopen":
			room.closed = false
			return
	var to: int = fields["to"]
	if not room.joiners.has(to):
		out.append(_error(socket, SignalCodec.WHY_NO_JOINER))
		return
	var joiner_socket := room.joiners[to]
	var joiner := _peers[joiner_socket]
	if decoded.type == "offer":
		var offer := {
			"id": fields["id"], "sdp": fields["sdp"], "ice_servers": _ice_servers.duplicate(true)
		}
		out.append(_send(joiner_socket, "offer", offer))
		return
	if joiner.candidates_down >= MAX_CANDIDATES:
		out.append(_error(socket, SignalCodec.WHY_CANDIDATES))
		return
	joiner.candidates_down += 1
	var candidate := {"mid": fields["mid"], "index": fields["index"], "cand": fields["cand"]}
	out.append(_send(joiner_socket, "candidate", candidate))


## A joiner's message goes to its room's host and nowhere else, whatever it names.
func _from_joiner(peer: Peer, decoded: SignalCodec.Decoded, out: Array[Outgoing]) -> void:
	var room := _rooms[peer.code]
	var fields := decoded.fields
	var joiner_socket: int = room.joiners[peer.number]
	if decoded.type == "answer":
		out.append(_send(room.host, "answer", {"from": peer.number, "sdp": fields["sdp"]}))
		return
	if peer.candidates_up >= MAX_CANDIDATES:
		out.append(_error(joiner_socket, SignalCodec.WHY_CANDIDATES))
		return
	peer.candidates_up += 1
	var candidate := {
		"from": peer.number, "mid": fields["mid"], "index": fields["index"], "cand": fields["cand"]
	}
	out.append(_send(room.host, "candidate", candidate))


func _send(socket: int, type: String, fields: Dictionary) -> Outgoing:
	var message: Dictionary = {"t": type, "v": SignalCodec.VERSION}
	message.merge(fields)
	return Outgoing.new(socket, message, false)


func _error(socket: int, why: String, close := false) -> Outgoing:
	return Outgoing.new(socket, {"t": "error", "v": SignalCodec.VERSION, "why": why}, close)
