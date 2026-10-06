class_name CodeRoom
extends RefCounted
## A host's room with a code (the M6 ADR §2.3): the WebRtcTransport that opens it at the
## signalling service, and with --signal=lan the LanSignalling this process serves itself on the
## host's port (TCP). The game and tools/run/headless_session.gd host through it alike.

var transport: WebRtcTransport
## The LanSignalling served here; null with a remote service.
var lan: LanSignalling
## What went wrong in open(); empty when nothing did.
var problem := ""


## A room for `mode` through `service` (a URL, or LaunchOptions.LAN_SIGNAL served on `port` and
## `bind`, 0 for any free one, handing out `lan_code` when given), on the game's `kinds`.
static func open(
	kinds: NetKindTable, mode: GameMode, service: String, port: int, bind: String, lan_code := ""
) -> CodeRoom:
	var room := CodeRoom.new()
	room.transport = WebRtcTransport.new(kinds)
	room.transport.signal_url = service
	room.transport.room_protocol = WireSchema.VERSION
	room.transport.room_content = ClientSession.content_of(mode)
	if service != LaunchOptions.LAN_SIGNAL:
		return room
	var served := (
		LanSignalling.new([], func() -> String: return lan_code)
		if not lan_code.is_empty()
		else LanSignalling.new()
	)
	if served.listen(port, bind) != OK:
		room.problem = "the signalling could not listen on TCP port %d" % port
		return room
	room.lan = served
	room.transport.signal_url = "ws://%s:%d" % [LaunchOptions.LOCALHOST, served.port()]
	# A --local host: everyone is on this machine, so host candidates on 127.0.0.1 only.
	room.transport.local_candidates = bind == LaunchOptions.LOCALHOST
	return room


## Each frame: the served signalling's sockets.
func poll() -> void:
	if lan != null:
		lan.poll()


## The room's code; empty before the service made the room, and after it went away.
func code() -> String:
	return transport.room_code()


## The socket to the service closed or could not open: no code is coming, or the one there was is
## gone (no reclaim), and nobody new can join with a code.
func gone() -> bool:
	return not transport.signalling_open()


func stop() -> void:
	if lan != null:
		lan.stop()
		lan = null
