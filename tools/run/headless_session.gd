extends SceneTree
## `tools\run.cmd host` and `tools\run.cmd join` (ARCHITECTURE §4.6, 3i): one headless session over
## ENet with the base mode from content/, which prints the roster, the phase and the counters as
## they change: a connectivity check between two machines, as #21 ran, and what the runner's
## `host` and `join` run with --headless (the game, client/app/game.tscn, runs them in windows).
## The arguments after -- are LaunchOptions' (client/app/), one of --host and --join required;
## the end reasons are said in words by EndReasons (client/app/).
## It lives in tools/, which may use everything (ARCHITECTURE §1), because it composes server/ and
## client/ in one process; the host's own client still reads nothing of HostSession, only what
## own_client delivers (invariant 2).
##
## Exit codes: 0 for a clean end (the host stopped; a welcomed client stopped, or its host ended
## the session); 1 when the host could not start or ended for an error, or a client never got in
## (refused, no answer, stopped before Welcome) or ended for any other reason; 2 for wrong
## arguments.

const MODE_PATH := "res://content/modes/base_mode.tres"
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

var _options: LaunchOptions
var _session: HostSession
var _host_node: HostNode
var _client: ClientSession
var _transport: NetTransport
## A --code host's room; null otherwise.
var _room: CodeRoom
var _shown_code := ""
var _finished := false
var _last_stop_check_ms := 0
var _last_counters_ms := 0
var _shown_roster := NOBODY
var _shown_phase := ""
var _shown_counters := ""


func _initialize() -> void:
	Engine.max_fps = MAX_FPS
	_options = LaunchOptions.parse(OS.get_cmdline_user_args())
	if not _options.problem.is_empty():
		_finish(EXIT_USAGE, _options.problem)
		return
	var mode := load(MODE_PATH) as GameMode
	if mode == null:
		_finish(EXIT_FAILED, "cannot load the game mode %s" % MODE_PATH)
		return
	var schema := WireSchema.game(OS.is_debug_build())
	if _options.hosting and _options.by_code:
		_room = CodeRoom.open(
			schema.kind_table(),
			mode,
			_options.signal_url,
			_options.port,
			_options.bind,
			_options.room
		)
		if not _room.problem.is_empty():
			_finish(EXIT_FAILED, "cannot host: %s" % _room.problem)
			return
		_transport = _room.transport
	elif _options.hosting:
		var enet := EnetTransport.new(schema.kind_table())
		enet.bind_address = _options.bind
		_transport = enet
	else:
		_transport = _options.target.transport(schema.kind_table())
	if _options.hosting:
		_start_host(mode, schema)
	else:
		_start_join(mode, schema)


func _process(_delta: float) -> bool:
	if _finished:
		return false
	var now := HostNode.now_usec()
	if _room != null:
		_room.poll()
		if _room.code() != _shown_code:
			_shown_code = _room.code()
			print("session: room code %s" % (_shown_code if not _shown_code.is_empty() else "gone"))
	_client.step(now)
	if _finished:
		return false
	_show_changes()
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_stop_check_ms >= STOP_CHECK_MS:
		_last_stop_check_ms = now_ms
		if _stop_requested():
			_stop()
		elif _runner_gone():
			print("session: the runner is gone (its alive file is missing or stale), stopping")
			_stop()
	return false


func _start_host(mode: GameMode, schema: WireSchema) -> void:
	_transport.peer_joined.connect(_on_peer_joined)
	_transport.peer_left.connect(_on_peer_left)
	_session = HostSession.new(_transport, schema)
	_session.ended.connect(_on_host_ended)
	if not _options.replay:
		_session.replay_dir = ""
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
	print(
		(
			"%s %s on %s:%d"
			% [LaunchOptions.HOSTING, mode.resource_path.get_file(), _options.bind, _options.port]
		)
	)
	if _options.bind == LaunchOptions.EVERY_INTERFACE:
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
	var target := _options.target
	var err := _transport.join(target.join_address(), target.port)
	if err != OK:
		_finish(EXIT_FAILED, "cannot join %s: %s" % [target.label(), error_string(err)])
		return
	print("session: joining %s" % target.label())


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
	var counters := _counters_text()
	var now_ms := Time.get_ticks_msec()
	if counters != _shown_counters and now_ms - _last_counters_ms >= COUNTERS_INTERVAL_MS:
		_last_counters_ms = now_ms
		_shown_counters = counters
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
	if peer == NetTransport.HOST_ID:
		print("session: own client connected")
	else:
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
	return EndReasons.text(reason)


## Asked to stop (the runner's stop file): close cleanly, so the clients see host_lost at once. A
## client that was not welcomed yet fails: a check that stops it never saw it join.
func _stop() -> void:
	_end(STOPPED)


func _end(reason: StringName) -> void:
	var welcomed := _client != null and _client.is_welcomed()
	_finish(
		exit_code(_options.hosting, welcomed, reason), end_text(_options.hosting, welcomed, reason)
	)


func _runner_gone() -> bool:
	return _options.runner_gone()


func _stop_requested() -> bool:
	return _options.stop_requested()


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
	if _room != null:
		_room.stop()
	quit(code)
