class_name HostNode
extends Node
## Steps a HostSession from the physics step with the real clock (ARCHITECTURE §4.5): its
## process_physics_priority runs it before the host's own client's nodes, so a step's messages to
## the own client are read in the same frame. Tests and the bots runner call HostSession.step with
## a clock of their own instead.
##
## The game's narrow handle on the host (§4.7, the M4 ADR's E18): host() builds and starts the
## session and keeps it private. The game reads only own_client, errors, end_reason, ended and a
## debug build's counters() and relay_counters(), and calls close(), so the host's own player sees
## nothing but what its ClientSession decoded. tools/ and the tests that need more use HostSession
## itself, and hand it to HostNode.new.
##
## Start the session with HostNode.now_usec() (HostSession.start's now_usec): the session counts
## host ticks from it, so any other clock makes the first step catch up the difference at once.
## Leaving the tree closes the session, so the node is never reparented. It runs while the tree is
## paused: a paused host would freeze every remote client.

## The session ended (HostSession.ended): every client sees host_lost.
signal ended(reason: StringName)

## Lower runs first: before any game node at the default 0.
const PHYSICS_PRIORITY := -100

## The host's own client, peer 1: the game runs a ClientSession on it. Null when not started.
var own_client: NetTransport:
	get:
		return _session.own_client if _session != null else null
## Why the start was refused, or why the session ended.
var errors: PackedStringArray:
	get:
		return _session.errors if _session != null else PackedStringArray()
## Why the session ended; empty while it runs.
var end_reason: StringName:
	get:
		return _session.end_reason if _session != null else &""
## The clock the session is stepped with, in microseconds: now_usec() unless a test sets one
## (the game's integration test runs a match on a simulated clock).
var clock := Callable()

var _session: HostSession


func _init(host_session: HostSession = null) -> void:
	_session = host_session
	process_physics_priority = PHYSICS_PRIORITY
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _session != null:
		_session.ended.connect(_on_ended)


## A host of `mode` on `transport` (an EnetTransport with the game's kind table; its bind address
## set) on `port`: the session started with every level's collision world and a seed from the
## system's entropy, one remote slot per remote player of the mode plus one, so the one too many
## hears `full` from core/. Check is_running(): when the start was refused, `errors` says why.
## `with_clock`: the clock to step it with (now_usec() when empty).
static func host(
	transport: NetTransport, mode: GameMode, port: int, with_clock := Callable()
) -> HostNode:
	var session := HostSession.new(transport)
	var node := HostNode.new(session)
	node.clock = with_clock
	session.start(mode, port, mode.max_players, node._now())
	return node


## The clock HostNode steps its session with, in microseconds.
static func now_usec() -> int:
	return Time.get_ticks_usec()


func is_running() -> bool:
	return _session != null and _session.is_running()


## Writes no replay when the session ends (the runner's selftest keeps the developer's newest).
func skip_replay() -> void:
	if _session != null:
		_session.replay_dir = ""


## Debug builds only (invariant 8): the session's counters of budgets and malformed messages for
## the debug overlay, which may show them at any time; empty in a release build.
func counters() -> Dictionary[StringName, int]:
	var found: Dictionary[StringName, int] = {}
	if not OS.is_debug_build() or _session == null:
		return found
	found[&"over_budget"] = _session.over_budget
	found[&"bad_payloads"] = _session.bad_payloads
	found[&"malformed_disconnects"] = _session.malformed_disconnects
	return found


## Debug builds only (E47 as amended): the voice relay's counters and the upload since the session
## started (HostSession.relay_counters); empty in a release build. The overlay never shows them
## during a Round (the M5 ADR §3 item 11, DebugOverlay.shows_relay).
func relay_counters() -> Dictionary[StringName, int]:
	if not OS.is_debug_build() or _session == null:
		var none: Dictionary[StringName, int] = {}
		return none
	return _session.relay_counters()


## Ends the session (the host leaves or quits): every client sees host_lost.
func close() -> void:
	if _session != null:
		_session.close()


func _physics_process(_delta: float) -> void:
	if _session != null:
		_session.step(_now())


func _exit_tree() -> void:
	close()


func _now() -> int:
	return clock.call() as int if clock.is_valid() else now_usec()


func _on_ended(reason: StringName) -> void:
	ended.emit(reason)
