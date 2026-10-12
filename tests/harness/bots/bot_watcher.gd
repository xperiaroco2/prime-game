class_name BotWatcher
extends RefCounted
## A connected peer that is not a player, for the leak test (ARCHITECTURE §4.6): the lurker, which
## connects and never sends Hello, and the refused bot, whose Hello the host refuses
## (`wrong_version`). It records every message it decodes; view_of of its peer holds at most the
## Rejected, so a server/ that sends *everyone* events, snapshots or voice to the transport's peers
## instead of core/'s recipients fails the test.
##
## Its runner joins it again (NetPlay._watcher_join_again, rejoin) while it never connected and its
## join was lost the way a bot's is joined again (JoinRetry: no answer, or no room at the
## signalling), MAX_JOINS joins at most (#509).

## The joins a watcher makes at most, as a networked chaos run's bots (ChaosRun.MAX_JOINS): its
## host is up in the same process before it joins, so a lost join is load, not a late host. The
## match cannot close joins on it: no bot acts while its join is open (NetPlay._watchers_settled),
## so three joins (a no-room end within the 5 s signalling cap plus the 0.5 s wait, an unanswered
## ENet one after its 5 s JOIN_TIMEOUT_MS) delay the run by about 16.5 s at most.
const MAX_JOINS := 3

## "lurker" or "refused".
var label: String
## The transport of its last join.
var transport: NetTransport
var view := DecodedView.new()
## Its joins: when the last one started, and why the earlier ones ended (the leak test names them).
var joins := JoinRetry.new(MAX_JOINS)
## Its peer id once connected; 0 before.
var peer := 0
## It sent a Hello.
var said_hello := false
## The host disconnected it (or closed).
var lost := false
## Why its join failed (connect_failed's reason, NetTransport.JOIN_*); empty while it never failed.
## The leak test names it when the watcher never connected (#483).
var failed_reason := &""
## Messages it received that did not decode.
var undecodable := 0

var _schema: WireSchema
var _hello: Dictionary = {}


## A watcher on `on_transport` (not joined yet); with `hello`, it sends that Hello once connected.
func _init(
	watcher_label: String, on_transport: NetTransport, schema: WireSchema, hello: Dictionary = {}
) -> void:
	label = watcher_label
	_schema = schema
	_hello = hello
	_listen(on_transport)


## The lurker: it never sends Hello.
static func lurker(on_transport: NetTransport, schema: WireSchema) -> BotWatcher:
	return BotWatcher.new("lurker", on_transport, schema)


## The refused bot: its Hello names a protocol version the host does not speak.
static func refused(on_transport: NetTransport, schema: WireSchema, content: int) -> BotWatcher:
	var hello := {"version": WireSchema.VERSION + 1, "content": content, "name": "", "key": "nokey"}
	return BotWatcher.new("refused", on_transport, schema, hello)


## Whether it sends a Hello once connected (the refused bot).
func sends_hello() -> bool:
	return not _hello.is_empty()


func poll() -> void:
	if transport.role() != NetTransport.Role.IDLE:
		transport.poll()


func close() -> void:
	transport.close()


## Joins again on `on_transport` (joining already) at `now_usec`, after its last join was lost
## (JoinRetry): that join's transport is closed and no longer heard, and its failure is cleared.
func rejoin(on_transport: NetTransport, now_usec: int) -> void:
	transport.connected.disconnect(_on_connected)
	transport.host_lost.disconnect(_on_lost)
	transport.connect_failed.disconnect(_on_failed)
	transport.packet_received.disconnect(_on_packet)
	transport.close()
	failed_reason = &""
	lost = false
	_listen(on_transport)
	joins.start(now_usec)


func _listen(on_transport: NetTransport) -> void:
	transport = on_transport
	transport.connected.connect(_on_connected)
	transport.host_lost.connect(_on_lost)
	transport.connect_failed.connect(_on_failed)
	transport.packet_received.connect(_on_packet)


func _on_connected(own_id: int) -> void:
	peer = own_id
	view.peer = own_id
	if _hello.is_empty():
		return
	var payload := _schema.encode(WireMessage.new(&"Hello", _hello))
	if transport.send(NetTransport.HOST_ID, _schema.kind_of(&"Hello"), payload) == OK:
		said_hello = true


func _on_lost() -> void:
	lost = true


func _on_failed(reason: StringName) -> void:
	failed_reason = reason
	lost = true


func _on_packet(_from: int, kind: int, payload: PackedByteArray) -> void:
	var message := _schema.decode(kind, payload)
	if message == null:
		undecodable += 1
	else:
		view.record(message)
