class_name ChaosMalformed
extends RefCounted
## The "malformed" chaos peer (ARCHITECTURE §4.5): it connects in the lobby and never sends a
## Hello, so it stays a peer that is not a player, in no rule and invisible to the players (§3.2).
## It sends, from a seeded RandomNumberGenerator: a few well-formed intents (a newcomer's are
## not_accepted,
## its MoveClaim dropped), its voice (never relayed: it is no player), one burst past the voice
## bucket, a debug kind (ForceRole naming bot 1's peer as a dissident), then malformed frames of
## every shape, a few per frame, until the host disconnects it for MALFORMED_LIMIT of them within
## the window, with one log line naming it. In the baseline run it connects and stays idle until the
## entry into Loading disconnects it (E14).

## Frames after its connection before it starts, so the bots' joins come first.
const START_AFTER_FRAMES := 30
## Malformed frames per frame, at most.
const PER_FRAME := 3
const BURST_VOICE := 520

var rng := RandomNumberGenerator.new()
var transport: NetTransport
var view := DecodedView.new()
## Its peer id once connected; 0 before.
var peer := 0
## The host disconnected it (or closed).
var lost := false
var undecodable := 0
## Whether it sends chaos (false in the baseline).
var active := true
## The labels it sent, with counts, for the report.
var sent: Dictionary[String, int] = {}

var _schema: WireSchema
var _send_raw: Callable
var _frames := 0
var _seq := ChaosFrames.CHAOS_SEQ * 2


func _init(
	on_transport: NetTransport, send_raw: Callable, schema: WireSchema, chaos_seed: int
) -> void:
	transport = on_transport
	_send_raw = send_raw
	_schema = schema
	rng.seed = chaos_seed
	transport.connected.connect(_on_connected)
	transport.host_lost.connect(_on_lost)
	transport.connect_failed.connect(_on_lost)
	transport.packet_received.connect(_on_packet)


func poll() -> void:
	if transport.role() != NetTransport.Role.IDLE:
		transport.poll()


func close() -> void:
	transport.close()


## One frame: its chaos, once connected, while connected. `host_peer` is bot 1's peer.
func act(host_peer: int) -> void:
	if not active or peer == 0 or lost:
		return
	_frames += 1
	if _frames < START_AFTER_FRAMES:
		return
	if _frames == START_AFTER_FRAMES:
		_first_words(host_peer)
		return
	# At most one LATEST frame NetFrame accepts per frame: the merge would supersede the others
	# before the codec sees them (counted as superseded, not as malformed).
	var latest := false
	for _i in rng.randi_range(1, PER_FRAME):
		var shape := rng.randi_range(0, ChaosFrames.Shape.size() - 1) as ChaosFrames.Shape
		var packet := ChaosFrames.malformed(shape, rng, _schema, peer)
		if packet.frame_valid and packet.lane == NetKindTable.Lane.LATEST:
			if latest:
				continue
			latest = true
		_send(packet)


## What a newcomer may well try before its malformed burst.
func _first_words(host_peer: int) -> void:
	_send(ChaosFrames.message(_schema, Intents.SET_READY, {"ready": true}, _next_seq()))
	_send(ChaosFrames.message(_schema, Intents.PICK_UP, {"item": ChaosOracle.NO_ITEM}, _next_seq()))
	var claim := ChaosFrames.claim(ChaosFrames.Claim.TELEPORT, _schema, 0, 0, Vector3.ZERO, 0)
	_send(claim)
	var role := {"role": "dissident"}
	_send(ChaosFrames.message(_schema, &"ForceRole", role, _next_seq(), host_peer))
	for i in BURST_VOICE:
		var fields := {"seq": i, "opus": LeakCheck.voice_frame(peer, i)}
		_send(ChaosFrames.message(_schema, &"VoiceUp", fields))


func _next_seq() -> int:
	_seq += 1
	return _seq


func _send(packet: ChaosFrames.Packet) -> void:
	if packet == null:
		push_error("chaos: the encoder refused a chaos message")
		return
	if packet.intent == &"ForceRole":
		# A debug kind from a peer other than 1 is malformed (E17).
		packet.expect = NetRejects.Reason.BAD_PAYLOAD
		packet.intent = &""
	if _send_raw.call(packet) as bool:
		sent[packet.label] = sent.get(packet.label, 0) + 1


func _on_connected(own_id: int) -> void:
	peer = own_id
	view.peer = own_id


func _on_lost() -> void:
	lost = true


func _on_packet(_from: int, kind: int, payload: PackedByteArray) -> void:
	var message := _schema.decode(kind, payload)
	if message == null:
		undecodable += 1
	else:
		view.record(message)
