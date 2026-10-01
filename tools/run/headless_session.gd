extends SceneTree
## `tools\run.cmd host` and `tools\run.cmd join` (ARCHITECTURE §4.6, 3i): one headless session over
## ENet with the base mode from content/, which prints the roster, the phase and the counters as
## they change. A connectivity check between two machines, as #21 ran; M4 gives it windows and the
## real client. Run it through the runner, which passes the arguments after --:
##   --host [--local]   host: a HostSession (stepped by a HostNode) and its own ClientSession on
##                      own_client; --local listens on 127.0.0.1 only, else on every interface
##   --join=<address>   join that host with a ClientSession over EnetTransport
##   --port=<p>         the UDP port (default DEFAULT_PORT)
##   --stop-file=<path> stop cleanly once this file exists (the runner's Ctrl+C and --seconds)
## It lives in tools/, which may use everything (ARCHITECTURE §1), because it composes server/ and
## client/ in one process; the host's own client still reads nothing of HostSession, only what
## own_client delivers (invariant 2).
##
## Exit codes: 0 for a clean end (the host stopped; a welcomed client stopped, or its host ended
## the session); 1 when the host could not start or ended for an error, or a client never got in
## (refused, no answer, stopped before Welcome) or ended for any other reason; 2 for wrong
## arguments.

const MODE_PATH := "res://content/modes/base_mode.tres"
## A placeholder, "not a decision".
const DEFAULT_PORT := 24600
const HOST_ARG := "--host"
const LOCAL_ARG := "--local"
const JOIN_ARG := "--join="
const PORT_ARG := "--port="
const STOP_ARG := "--stop-file="
const LOCALHOST := "127.0.0.1"
const EVERY_INTERFACE := "*"
## The runner starts the local clients once the host printed this.
const HOSTING := "session: hosting"
const STOP_CHECK_MS := 200
## A changed counter is printed at most this often; the roster and the phase at once.
const COUNTERS_INTERVAL_MS := 1000
## The roster before Welcome: not printed until it changes.
const NOBODY := "(empty)"
## Headless Godot runs its frames as fast as it can: a session that runs for an hour needs no more.
const MAX_FPS := 120
const EXIT_OK := 0
const EXIT_FAILED := 1
const EXIT_USAGE := 2
## The end reason of a process the runner stopped (its stop file), next to ClientSession's reasons.
const STOPPED := &"stopped"
## Why a join ended before Welcome, as a person reads it.
const REFUSALS: Dictionary[StringName, String] = {
	&"wrong_version":
	"the host runs another protocol version: put both machines on the same commit",
	&"wrong_content":
	(
		"the host's game content (content/ or levels/) differs from this machine's: put both"
		+ " machines on the same commit"
	),
	&"joins_closed": "the host's match is under way: join again when it is back in the lobby",
	&"full": "the host's lobby is full",
	&"connect_failed":
	(
		"no answer from the host: check that it runs, the address and the port, and that its"
		+ " firewall lets UDP in"
	),
}

var _options: Options
var _session: HostSession
var _host_node: HostNode
var _client: ClientSession
var _transport: EnetTransport
var _finished := false
var _last_stop_check_ms := 0
var _last_counters_ms := 0
var _shown_roster := NOBODY
var _shown_phase := ""
var _shown_counters := ""
var _pending_counters := ""


## The arguments after --.
class Options:
	extends RefCounted
	var hosting := false
	var port := DEFAULT_PORT
	var address := ""
	var bind := EVERY_INTERFACE
	var stop_file := ""
	## What is wrong with the arguments; empty when nothing is.
	var problem := ""

	static func parse(args: PackedStringArray) -> Options:
		var options := Options.new()
		options.problem = options._read(args)
		return options

	func _read(args: PackedStringArray) -> String:
		var joining := false
		var local := false
		for arg in args:
			if arg == HOST_ARG:
				hosting = true
			elif arg == LOCAL_ARG:
				local = true
			elif arg.begins_with(JOIN_ARG):
				joining = true
				address = arg.trim_prefix(JOIN_ARG)
			elif arg.begins_with(PORT_ARG):
				var text := arg.trim_prefix(PORT_ARG)
				port = text.to_int() if text.is_valid_int() else 0
				if port < 1 or port > 65535:
					return "%s takes a port between 1 and 65535, got '%s'" % [PORT_ARG, text]
			elif arg.begins_with(STOP_ARG):
				stop_file = arg.trim_prefix(STOP_ARG)
			else:
				return "unknown argument '%s'" % arg
		if hosting == joining:
			return "give either %s or %s<address>" % [HOST_ARG, JOIN_ARG]
		if joining and address.is_empty():
			return "%s needs the host's address" % JOIN_ARG
		if local and not hosting:
			return "%s is for the host only" % LOCAL_ARG
		bind = LOCALHOST if local else EVERY_INTERFACE
		return ""


func _initialize() -> void:
	Engine.max_fps = MAX_FPS
	_options = Options.parse(OS.get_cmdline_user_args())
	if not _options.problem.is_empty():
		_finish(EXIT_USAGE, _options.problem)
		return
	var mode := load(MODE_PATH) as GameMode
	if mode == null:
		_finish(EXIT_FAILED, "cannot load the game mode %s" % MODE_PATH)
		return
	var schema := WireSchema.game(OS.is_debug_build())
	_transport = EnetTransport.new(schema.kind_table())
	if _options.hosting:
		_start_host(mode, schema)
	else:
		_start_join(mode, schema)


func _process(_delta: float) -> bool:
	if _finished:
		return false
	var now := HostNode.now_usec()
	_client.step(now)
	if _finished:
		return false
	_show_changes()
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_stop_check_ms >= STOP_CHECK_MS:
		_last_stop_check_ms = now_ms
		if _stop_requested():
			_stop()
	return false


func _start_host(mode: GameMode, schema: WireSchema) -> void:
	_transport.bind_address = _options.bind
	_transport.peer_joined.connect(_on_peer_joined)
	_transport.peer_left.connect(_on_peer_left)
	_session = HostSession.new(_transport, schema)
	_session.ended.connect(_on_host_ended)
	# The transport counts remote clients only: one slot more than the mode's remote players, so
	# the one too many hears `full` from core/ instead of a silent refusal by ENet.
	if not _session.start(mode, _options.port, mode.max_players, HostNode.now_usec()):
		_finish(EXIT_FAILED, "cannot host: %s" % "; ".join(_session.errors))
		return
	_host_node = HostNode.new(_session)
	root.add_child(_host_node)
	_client = ClientSession.new(_session.own_client, mode, schema)
	_client.ended.connect(_on_client_ended)
	_client.welcomed.connect(_on_welcomed)
	print("%s %s on %s:%d" % [HOSTING, mode.resource_path.get_file(), _options.bind, _options.port])
	if _options.bind == EVERY_INTERFACE:
		var addresses := _lan_addresses()
		print(
			(
				"session: from another machine: tools\\run.cmd join <address> --port %d (this one: %s)"
				% [
					_options.port,
					", ".join(addresses) if not addresses.is_empty() else "no LAN address"
				]
			)
		)


func _start_join(mode: GameMode, schema: WireSchema) -> void:
	_client = ClientSession.new(_transport, mode, schema)
	_client.ended.connect(_on_client_ended)
	_client.welcomed.connect(_on_welcomed)
	var err := _transport.join(_options.address, _options.port)
	if err != OK:
		_finish(
			EXIT_FAILED,
			"cannot join %s:%d: %s" % [_options.address, _options.port, error_string(err)]
		)
		return
	print("session: joining %s:%d" % [_options.address, _options.port])


## Prints the roster and the phase when they changed, and the counters at most once a second.
func _show_changes() -> void:
	var model := _client.model
	var roster := roster_text(model)
	if roster != _shown_roster:
		_shown_roster = roster
		print("session: roster: %s" % roster)
	if String(model.phase) != _shown_phase:
		_shown_phase = String(model.phase)
		print("session: phase: %s" % _shown_phase)
	_pending_counters = _counters_text()
	var now_ms := Time.get_ticks_msec()
	if _pending_counters != _shown_counters and now_ms - _last_counters_ms >= COUNTERS_INTERVAL_MS:
		_last_counters_ms = now_ms
		_shown_counters = _pending_counters
		print("session: counters: %s" % _shown_counters)


## The roster by name: "Player1 [1] ready, Player2 [3141]".
static func roster_text(model: ClientModel) -> String:
	if model.roster.is_empty():
		return NOBODY
	var peers: Array[int] = []
	peers.assign(model.roster.keys())
	peers.sort_custom(
		func(a: int, b: int) -> bool:
			return model.roster[a].name.naturalnocasecmp_to(model.roster[b].name) < 0
	)
	var parts := PackedStringArray()
	for peer in peers:
		var member: ClientModel.Member = model.roster[peer]
		parts.append("%s [%d]%s" % [member.name, peer, " ready" if member.ready else ""])
	return ", ".join(parts)


## The transport's counters, the host session's (budgets, malformed messages, voice) on the host,
## and the client's undecodable messages.
func _counters_text() -> String:
	var parts := PackedStringArray()
	parts.append("rejected %d" % _transport.rejects.total())
	parts.append("latest_superseded %d" % _transport.latest_superseded)
	if _session != null:
		parts.append("over_budget %d" % _session.over_budget)
		parts.append("bad_payloads %d" % _session.bad_payloads)
		parts.append("malformed_disconnects %d" % _session.malformed_disconnects)
		parts.append("voice_dropped %d" % _session.voice_dropped())
	parts.append("client_bad_payloads %d" % _client.bad_payloads)
	return ", ".join(parts)


static func _lan_addresses() -> PackedStringArray:
	var found := PackedStringArray()
	for address in IP.get_local_addresses():
		var ipv4 := address.is_valid_ip_address() and not address.contains(":")
		if ipv4 and not address.begins_with("127."):
			found.append(address)
	return found


func _on_peer_joined(peer: int) -> void:
	print("session: peer %d connected" % peer)


func _on_peer_left(peer: int) -> void:
	print("session: peer %d left" % peer)


func _on_welcomed(own_peer: int) -> void:
	var member: ClientModel.Member = _client.model.roster.get(own_peer)
	print("session: welcomed as %s [%d]" % [member.name if member != null else "?", own_peer])


func _on_client_ended(reason: StringName) -> void:
	if _finished:
		return
	# The host stopped on the shared stop file before this client polled it: a stop, not a loss.
	if _stop_requested():
		reason = STOPPED
	_end(reason)


func _on_host_ended(reason: StringName) -> void:
	if _finished:
		return
	_finish(EXIT_FAILED, "the host session ended: %s %s" % [reason, "; ".join(_session.errors)])


## The exit code when this process's client ends with `reason` (or STOPPED).
static func exit_code(hosting: bool, welcomed: bool, reason: StringName) -> int:
	if reason == STOPPED:
		return EXIT_OK if hosting or welcomed else EXIT_FAILED
	if hosting:
		# The host's own client ended first (a failed load, say): the host ends the session.
		return EXIT_FAILED
	if welcomed and reason in [ClientSession.HOST_LOST, ClientSession.LEFT]:
		return EXIT_OK
	return EXIT_FAILED


## Why the process ends, as the last `session:` line says it.
static func end_text(hosting: bool, welcomed: bool, reason: StringName) -> String:
	if reason == STOPPED:
		return "stopped" if hosting or welcomed else "stopped before the host welcomed it"
	if hosting:
		return "the host's own client ended: %s" % reason
	if not welcomed:
		return "could not join: %s" % ended_text(reason)
	return "the session ended: %s" % ended_text(reason)


static func ended_text(reason: StringName) -> String:
	if REFUSALS.has(reason):
		return "%s (%s)" % [reason, REFUSALS[reason]]
	if reason == ClientSession.HOST_LOST:
		return "host_lost (the host closed, or the connection was lost)"
	return String(reason)


## Asked to stop (the runner's stop file): close cleanly, so the clients see host_lost at once. A
## client that was not welcomed yet fails: a check that stops it never saw it join.
func _stop() -> void:
	_end(STOPPED)


func _end(reason: StringName) -> void:
	var welcomed := _client != null and _client.is_welcomed()
	_finish(
		exit_code(_options.hosting, welcomed, reason), end_text(_options.hosting, welcomed, reason)
	)


func _stop_requested() -> bool:
	return not _options.stop_file.is_empty() and FileAccess.file_exists(_options.stop_file)


## Prints the final counters and why it ends, closes the session and quits with `code`.
func _finish(code: int, why: String) -> void:
	if _finished:
		return
	_finished = true
	if _client != null:
		_shown_counters = _counters_text()
		print("session: counters: %s" % _shown_counters)
	print("session: %s" % why)
	if _session != null and _session.is_running():
		_session.close()
	if _client != null and not _client.is_ended():
		_client.leave()
	quit(code)
