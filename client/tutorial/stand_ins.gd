class_name StandIns
extends Node
## The solo tutorial's stand-ins (docs/design/tutorial.md §2.2: D25, D26, D35 (a), E67; ARCHITECTURE
## §4.7.43): COUNT in-process players of the tutorial's private LoopbackHub, so lesson 6 has someone
## down to raise and lesson 7 someone to watch. Each is a ClientSession on a LoopbackTransport of
## its own that joins the hub's host on `port` (join_host()) and then only:
## - sends Hello with no name (#550's ""), so the host names it as any joiner (Player<n>);
## - sends SetReady(true) once welcomed;
## - acknowledges LoadMatch at once (load_levels off, as the bots do: it loads no scene);
## - claims standing still where the host put it: the session's own claim from its last Welcome or
##   Correction, at rest on the floor, in every phase that accepts a claim.
## Nothing else: no other intent, no voice. Lessons stage it from the host (NextStage), never by
## scripting its client.
##
## Each session runs on a SessionNode of its own (its step clock and catch-up) at PHYSICS_PRIORITY:
## after the host's HostNode (-100) and before the own session (-90), every physics frame, also
## while the tree is paused. The game never reads a stand-in's model: what the player sees of one
## comes from the own session, like any other player's. Only this file names a stand-in's session
## (tests/unit/client/tutorial/stand_ins_source_test.gd holds it).

## Two (D26): one to raise in lesson 6, and another to switch to while watching in lesson 7.
const COUNT := 2
const PHYSICS_PRIORITY := -95

var _sessions: Array[ClientSession] = []
var _transports: Array[NetTransport] = []
var _port := 0


## `hub` and `port`: the tutorial's host; `mode`: the client's own copy of its mode (Hello's
## content hash); `clock`: the real clock of the step count's catch-up (SessionNode.real_clock).
func _init(
	hub: LoopbackHub, mode: GameMode, port: int, clock := Callable(), schema: WireSchema = null
) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_port = port
	var wire := schema if schema != null else WireSchema.game(OS.is_debug_build())
	for i in COUNT:
		var transport := LoopbackTransport.new(wire.kind_table(), hub)
		var session := ClientSession.new(transport, mode, wire)
		session.load_levels = false
		session.welcomed.connect(_on_welcomed.bind(session))
		var node := SessionNode.new(session)
		node.process_physics_priority = PHYSICS_PRIORITY
		node.real_clock = clock
		node.name = "StandIn%d" % (i + 1)
		add_child(node)
		_sessions.append(session)
		_transports.append(transport)


## Joins the host, in order: peers 2 and 3 on a fresh hub. GameTutorial calls it once the own
## player is welcomed, so the host's join count names the own player first (Player1 without a
## name of its own) and the stand-ins Player2 and Player3 (the design's 2.2). A second call does
## nothing.
func join_host() -> void:
	for transport: NetTransport in _transports:
		if transport.role() == NetTransport.Role.IDLE:
			transport.join(LaunchOptions.LOCALHOST, _port)


## Leaving the tree leaves the session: the host sees them go.
func _exit_tree() -> void:
	for session: ClientSession in _sessions:
		if not session.is_ended():
			session.leave()


## How many stand-ins there are.
func count() -> int:
	return _sessions.size()


## How many the host has welcomed and not lost.
func welcomed() -> int:
	var found := 0
	for session: ClientSession in _sessions:
		if session.is_welcomed() and not session.is_ended():
			found += 1
	return found


## The Corrections the host sent for refused claims, all stand-ins together: 0 while each stands.
func corrections() -> int:
	var found := 0
	for session: ClientSession in _sessions:
		found += session.corrections
	return found


func _on_welcomed(_own_peer: int, session: ClientSession) -> void:
	session.send_intent(Intents.SET_READY, {"ready": true})
