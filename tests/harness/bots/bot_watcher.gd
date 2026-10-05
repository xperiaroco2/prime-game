class_name BotWatcher
extends RefCounted
## A connected peer that is not a player, for the leak test (ARCHITECTURE §4.6): the lurker, which
## connects and never sends Hello, and the refused bot, whose Hello the host refuses
## (`wrong_version`). It records every message it decodes; view_of of its peer holds at most the
## Rejected, so a server/ that sends *everyone* events, snapshots or voice to the transport's peers
## instead of core/'s recipients fails the test.

## "lurker" or "refused".
var label: String
var transport: NetTransport
var view := DecodedView.new()
## Its peer id once connected; 0 before.
var peer := 0
## It sent a Hello.
var said_hello := false
## The host disconnected it (or closed).
var lost := false
## Messages it received that did not decode.
var undecodable := 0

var _schema: WireSchema
var _hello: Dictionary = {}


## A watcher on `on_transport` (not joined yet); with `hello`, it sends that Hello once connected.
func _init(
	watcher_label: String, on_transport: NetTransport, schema: WireSchema, hello: Dictionary = {}
) -> void:
	label = watcher_label
	transport = on_transport
	_schema = schema
	_hello = hello
	transport.connected.connect(_on_connected)
	transport.host_lost.connect(_on_lost)
	transport.connect_failed.connect(_on_lost.unbind(1))
	transport.packet_received.connect(_on_packet)


## The lurker: it never sends Hello.
static func lurker(on_transport: NetTransport, schema: WireSchema) -> BotWatcher:
	return BotWatcher.new("lurker", on_transport, schema)


## The refused bot: its Hello names a protocol version the host does not speak.
static func refused(on_transport: NetTransport, schema: WireSchema, content: int) -> BotWatcher:
	var hello := {"version": WireSchema.VERSION + 1, "content": content}
	return BotWatcher.new("refused", on_transport, schema, hello)


## Whether it sends a Hello once connected (the refused bot).
func sends_hello() -> bool:
	return not _hello.is_empty()


func poll() -> void:
	if transport.role() != NetTransport.Role.IDLE:
		transport.poll()


func close() -> void:
	transport.close()


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


func _on_packet(_from: int, kind: int, payload: PackedByteArray) -> void:
	var message := _schema.decode(kind, payload)
	if message == null:
		undecodable += 1
	else:
		view.record(message)
