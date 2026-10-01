extends RefCounted
## A HostSession over a LoopbackHub with a fake clock (ARCHITECTURE §4.5, §4.6): the host's own
## ClientSession (peer 1), ClientSessions joined over the hub, and raw clients that send what a
## ClientSession never would. The match and every client keep their history, so a test compares
## what each peer decoded with Match.view_of. A host freeze is a jump of the host's clock while the
## clients go on stepping.
##
## The mode is FixtureBaseMode's with res:// level paths (the wire carries only those; the files
## need not exist: ContentFingerprint counts a missing one as missing on both sides), proximity
## voice in Lobby and Countdown, FixtureVoice in Round and none in End.

const WireSamples := preload("res://tests/unit/net/messages/wire_samples.gd")

const PORT := 7300
const LOBBY := "res://tests/fixtures/server/lobby.tscn"
const MAP := "res://tests/fixtures/server/map.tscn"
const SMALL_MAP := "res://tests/fixtures/server/small_map.tscn"
## One physics frame at 60 Hz, in microseconds.
const FRAME_USEC := 16667
const SECOND := 1000000
const SEED := 7
## Lobby and Countdown hear within this many metres; the lobby markers are 2 m apart in x.
const NEAR_M := 3.0

var schema := WireSchema.game(true)
var hub := LoopbackHub.new()
var transport: LoopbackTransport
var session: HostSession
var mode: GameMode
## The fake clock, in microseconds.
var now := SECOND
var started := false
## The host's own client, when the harness made one.
var own: ClientSession
var clients: Array[ClientSession] = []
var raws: Array[RawClient] = []
## What the observer saw, one entry per Match call: "<tick> <command kind or tick> <phase>".
var calls: Array[String] = []
## The MoveClaims applied, by the phase they were applied in.
var claims_in: Dictionary[StringName, int] = {}


## A client that sends raw messages and records every message it decodes, in arrival order.
class RawClient:
	extends RefCounted
	var transport: LoopbackTransport
	var schema: WireSchema
	var received: Array[WireMessage] = []
	var peer := 0
	var lost := false

	func _init(wire: WireSchema, hub: LoopbackHub, port: int) -> void:
		schema = wire
		transport = LoopbackTransport.new(wire.kind_table(), hub)
		transport.connected.connect(_on_connected)
		transport.host_lost.connect(_on_host_lost)
		transport.packet_received.connect(_on_packet)
		transport.join("loopback", port)

	func poll() -> void:
		transport.poll()

	func send(message: WireMessage) -> Error:
		var payload := schema.encode(message)
		if payload.is_empty():
			return ERR_INVALID_DATA
		return transport.send(NetTransport.HOST_ID, schema.kind_of(message.name), payload)

	## Sends `payload` as a message of `kind`, whatever it holds.
	func send_bytes(kind: int, payload: PackedByteArray) -> Error:
		return transport.send(NetTransport.HOST_ID, kind, payload)

	func hello(content: int, version: int = WireSchema.VERSION) -> Error:
		return send(WireMessage.new(&"Hello", {"version": version, "content": content}))

	func names() -> Array[StringName]:
		var found: Array[StringName] = []
		for message: WireMessage in received:
			found.append(message.name)
		return found

	func named(message_name: StringName) -> Array[WireMessage]:
		var found: Array[WireMessage] = []
		for message: WireMessage in received:
			if message.name == message_name:
				found.append(message)
		return found

	func _on_connected(own_id: int) -> void:
		peer = own_id

	func _on_host_lost() -> void:
		lost = true

	func _on_packet(_from: int, kind: int, payload: PackedByteArray) -> void:
		var message := schema.decode(kind, payload)
		if message != null:
			received.append(message)


func _init(
	game_mode: GameMode = null, with_own_client := true, host_schema: WireSchema = null
) -> void:
	mode = game_mode if game_mode != null else fixture_mode()
	var wire := host_schema if host_schema != null else schema
	transport = LoopbackTransport.new(wire.kind_table(), hub)
	session = HostSession.new(transport, wire)
	session.replay_dir = ""
	session.observer = _on_call
	started = session.start_with(mode, FlatWorldQuery.new(), layouts(), PORT, 8, now, SEED)
	if started:
		session.game.keep_history = true
		if with_own_client:
			own = _client_on(session.own_client, mode)


## FixtureBaseMode's mode with res:// levels and voice rules (the class comment).
static func fixture_mode() -> GameMode:
	var made := FixtureBaseMode.mode()
	made.lobby_level = LOBBY
	made.maps = PackedStringArray([MAP, SMALL_MAP])
	var near := ProximityVoice.new()
	near.radius_m = NEAR_M
	made.find_phase(&"lobby").voice_rule = near
	made.find_phase(&"countdown").voice_rule = near
	made.find_phase(&"round").voice_rule = FixtureVoice.new()
	return made


## FixtureBaseMode's layouts under the res:// paths.
static func layouts() -> Dictionary[String, LevelLayout]:
	var renamed := {
		FixtureBaseMode.LOBBY: LOBBY, FixtureBaseMode.MAP: MAP, FixtureBaseMode.SMALL_MAP: SMALL_MAP
	}
	var found: Dictionary[String, LevelLayout] = {}
	var original := FixtureBaseMode.layouts()
	for path: String in original:
		var new_path: String = renamed[path]
		var layout := LevelLayout.new(new_path)
		for tag: StringName in original[path].tags():
			for at: Vector3 in original[path].positions(tag):
				layout.add_marker(tag, at)
		found[new_path] = layout
	return found


## A ClientSession joined over the hub with its own copy of `client_mode` (the host's by default).
func join(client_mode: GameMode = null) -> ClientSession:
	var joining := LoopbackTransport.new(schema.kind_table(), hub)
	joining.join("loopback", PORT)
	return _client_on(joining, client_mode if client_mode != null else mode)


## A raw client joined over the hub.
func raw() -> RawClient:
	var made := RawClient.new(schema, hub, PORT)
	raws.append(made)
	return made


## One frame: the host steps, then every client.
func pump(usec := FRAME_USEC) -> void:
	now += usec
	session.step(now)
	_step_clients()


func pump_frames(frames: int) -> void:
	for _i in frames:
		pump()


func pump_seconds(seconds: float) -> void:
	pump_frames(ceili(seconds * SECOND / FRAME_USEC))


## Frames pass for the clients while the host is frozen (it does not step); the next pump() thaws
## it.
func freeze_host(seconds: float) -> void:
	for _i in ceili(seconds * SECOND / FRAME_USEC):
		now += FRAME_USEC
		_step_clients()


## Pumps until `done` returns true, at most `frames` frames.
func pump_until(done: Callable, frames: int) -> bool:
	for _i in frames:
		if done.call():
			return true
		pump()
	return done.call()


## Pumps until every client is welcomed.
func welcome_all() -> bool:
	return pump_until(_all_welcomed, 20)


## Every client says it is ready, and the match runs until `phase`.
func run_until_phase(phase: StringName, frames: int = 900) -> bool:
	return pump_until(func() -> bool: return session.game.phase_id() == phase, frames)


func ready_all() -> void:
	for client: ClientSession in clients:
		if client.is_welcomed() and not client.is_ended():
			client.send_intent(Intents.SET_READY, {"ready": true})


func peer_of(client: ClientSession) -> int:
	return client.model.own_peer


## The difference between what `client` decoded and view_of its peer (§4.6): the events in order
## (name and fields, by type), each decoded snapshot's avatars, and each frame's speaker for its
## tick. Empty when they agree.
func mismatches(client: ClientSession) -> PackedStringArray:
	var found := PackedStringArray()
	var view := session.game.view_of(peer_of(client))
	var decoded := client.view.events
	if decoded.size() != view.events.size():
		found.append("%d events decoded, %d in view_of" % [decoded.size(), view.events.size()])
	for i in mini(decoded.size(), view.events.size()):
		var event := view.events[i]
		if decoded[i].name != event.event_name():
			found.append("event %d: %s, view_of %s" % [i, decoded[i].name, event.event_name()])
		elif not WireSamples.same(decoded[i].fields, event.to_dict()):
			found.append(
				(
					"event %d %s: %s, view_of %s"
					% [i, event.event_name(), decoded[i].fields, event.to_dict()]
				)
			)
	for at_tick: int in client.view.snapshots:
		if not view.snapshots.has(at_tick):
			found.append("a snapshot of tick %d that view_of lacks" % at_tick)
		elif client.view.snapshots[at_tick]["avatars"] != view.snapshots[at_tick]["avatars"]:
			found.append("the snapshot of tick %d differs" % at_tick)
	var heard := client.view.speakers()
	for at_tick: int in heard:
		var allowed: PackedInt32Array = view.speakers.get(at_tick, PackedInt32Array())
		for speaker: int in heard[at_tick]:
			if not allowed.has(speaker):
				found.append(
					"voice of %d under tick %d, which view_of does not allow" % [speaker, at_tick]
				)
	return found


## The VoiceDowns `client` decoded, as "speaker:tick:seq".
func voice_of(client: ClientSession) -> Array[String]:
	var found: Array[String] = []
	for key: Vector2i in client.view.voice:
		for opus: PackedByteArray in client.view.voice[key]:
			found.append("%d:%d:%s" % [key.x, key.y, opus.hex_encode()])
	return found


func close() -> void:
	for client: ClientSession in clients:
		if not client.is_ended():
			client.leave()
	for each: RawClient in raws:
		each.transport.close()
	session.close()


func _client_on(on: NetTransport, client_mode: GameMode) -> ClientSession:
	var client := ClientSession.new(on, client_mode, schema)
	client.keep_history = true
	client.load_levels = false
	clients.append(client)
	return client


func _step_clients() -> void:
	for client: ClientSession in clients:
		client.step(now)
	for each: RawClient in raws:
		each.poll()


func _all_welcomed() -> bool:
	for client: ClientSession in clients:
		if not client.is_welcomed():
			return false
	return true


func _on_call(at_tick: int, command: MatchCommand, _slice: Array[EmittedEvent]) -> void:
	var phase := session.game.phase_id()
	var what := String(command.kind) if command != null else "tick"
	calls.append("%d %s %s" % [at_tick, what, phase])
	if command != null and command.kind == Intents.MOVE_CLAIM:
		claims_in[phase] = claims_in.get(phase, 0) + 1
