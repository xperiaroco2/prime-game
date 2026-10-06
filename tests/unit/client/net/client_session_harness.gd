extends RefCounted
## A ClientSession joined over a LoopbackHub to a scripted host: the tests encode the host's
## messages with the codec from core/'s own events (so they are what a HostSession would send) and
## read back what the client sent. No HostSession: the end-to-end tests come with 3f (#100).

const PORT := 7100
const TINY_MAP := "res://tests/fixtures/client/tiny_map.tscn"
## Listed by the mode but absent, for a failed load.
const MISSING_MAP := "res://tests/fixtures/client/missing_map.tscn"
## One physics frame at 60 Hz, in microseconds.
const FRAME_USEC := 16667

var schema := WireSchema.game(true)
var hub := LoopbackHub.new()
var host := LoopbackTransport.new(schema.kind_table(), hub)
var client := LoopbackTransport.new(schema.kind_table(), hub)
var mode := FixtureBaseMode.mode()
var session: ClientSession
## The client's peer id on the hub.
var peer := 0
## The simulated clock, in microseconds.
var now := 1000000
## What the clients sent, decoded as the host would, and who sent each.
var sent: Array[WireMessage] = []
var senders: Array[int] = []
## ended(reason) as it fired.
var endings: Array[StringName] = []


func _init(load_levels := true) -> void:
	mode.lobby_level = TINY_MAP
	mode.maps = PackedStringArray([TINY_MAP, MISSING_MAP])
	host.host(PORT, 8)
	# Methods, not lambdas: a lambda that reads a member holds this harness, and the host it holds
	# would hold the lambda, a cycle that leaks both.
	host.peer_joined.connect(_on_peer_joined)
	host.packet_received.connect(_on_host_packet)
	client.join("127.0.0.1", PORT)
	session = ClientSession.new(client, mode, schema)
	session.keep_history = true
	session.load_levels = load_levels
	session.ended.connect(_on_ended)
	pump()


## One frame: the client steps (polls, loads, claims), then the host reads what it sent.
func pump(usec := FRAME_USEC) -> void:
	now += usec
	host.poll()
	session.step(now)
	host.poll()


## The host's messages reach the session with no step: a threaded load a LoadMatch starts is still
## waited for, however fast the loader thread is (a step would advance it in the same frame).
func deliver() -> void:
	host.poll()
	client.poll()


## Sends a core/ event to the client as the host's codec would encode it.
func send(event: MatchEvent) -> void:
	send_message(WireMessage.new(event.event_name(), event.to_dict()))


func send_message(message: WireMessage) -> void:
	var payload := schema.encode(message)
	assert(not payload.is_empty(), "the test's message does not encode")
	host.send(peer, schema.kind_of(message.name), payload)


## Welcomes the client into `phase` with epoch `epoch`, one other player (peer 1) in the roster.
func welcome(phase := &"lobby", epoch := 1) -> WelcomeEvent:
	var event := WelcomeEvent.new(peer, Vector3(1, 0, 2), epoch)
	(
		event
		. roster
		. assign(
			[
				{"peer": 1, "name": "Player1", "ready": true},
				{"peer": peer, "name": "Player2", "ready": false},
			]
		)
	)
	event.settings = {&"knives": 2, &"circles": 1}
	event.map = TINY_MAP
	event.phase = phase
	event.positions = {1: Vector3(5, 0, 5)}
	send(event)
	pump()
	return event


## The messages the client sent of one name, in order.
func sent_named(message_name: StringName) -> Array[WireMessage]:
	var found: Array[WireMessage] = []
	for message: WireMessage in sent:
		if message.name == message_name:
			found.append(message)
	return found


## Pumps until the client sent a message of `message_name`, at most `frames` frames.
func pump_until_sent(message_name: StringName, frames: int) -> bool:
	for i in frames:
		if not sent_named(message_name).is_empty():
			return true
		pump()
	return not sent_named(message_name).is_empty()


func close() -> void:
	session.leave()
	host.close()


## The claims the clients sent, in order: every MoveClaim and every MoveClaimReliable but a
## resend (#429), each once.
func claims() -> Array[WireMessage]:
	return _claims(false, -1)


## The MoveClaimReliable resends, in order: the twins that repeat the claim right before them (its
## epoch and client tick), which ClientSession sends right before a player action (#429).
func resends() -> Array[WireMessage]:
	return _claims(true, -1)


## How many claims `from_peer` sent (claims(), its own only).
func claims_from(from_peer: int) -> int:
	return _claims(false, from_peer).size()


## Each claim (MoveClaim or its twin) in order, the resends only or every other one; of every
## sender, or of `from_peer` only.
func _claims(resent: bool, from_peer: int) -> Array[WireMessage]:
	var found: Array[WireMessage] = []
	var last: Dictionary[int, WireMessage] = {}
	for i in sent.size():
		var message := sent[i]
		if message.name != Intents.MOVE_CLAIM and message.name != WireSchema.RELIABLE_CLAIM:
			continue
		var before: WireMessage = last.get(senders[i])
		var again: bool = (
			message.name == WireSchema.RELIABLE_CLAIM
			and before != null
			and before.fields["epoch"] == message.fields["epoch"]
			and before.fields["client_tick"] == message.fields["client_tick"]
		)
		last[senders[i]] = message
		if again == resent and (from_peer < 0 or senders[i] == from_peer):
			found.append(message)
	return found


## The first to join is this harness's client; a test may link the host's own client later.
func _on_peer_joined(joined: int) -> void:
	if peer == 0:
		peer = joined


func _on_ended(reason: StringName) -> void:
	endings.append(reason)


func _on_host_packet(from_peer: int, kind: int, payload: PackedByteArray) -> void:
	var message := schema.decode(kind, payload)
	assert(message != null, "the client sent a message the host cannot decode")
	sent.append(message)
	senders.append(from_peer)
