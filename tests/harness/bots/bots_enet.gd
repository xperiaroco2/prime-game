class_name BotsEnet
extends NetPlay
## One instance of the bots runner over ENet (ARCHITECTURE §4.6; E12): `--instances N` runs one
## scenario on 127.0.0.1, on the real clock, one process per bot. Instance 1 hosts a HostSession
## (keep_history on) with bot 1 as its own client, and runs the lurker and the refused bot on ENet
## in its process; instance i > 1 runs bot i alone. The owner calls start() once, then step() every
## frame until done() is true, then finish().
##
## Bot numbers to peer ids, out of band (harmless: peer ids are public in the roster): each
## instance writes its peer id to `peer-<i>` in the scenario's folder on `connected`; bot 1 reads
## them, writes the whole map to `peers` once it knows every bot that joins at the start (and again
## when a later one connects), and only then sends the ForceRoles; every other bot reads `peers`
## before its first step, and again when it meets a bot number it does not know.
##
## Each bot writes its view file (ViewFile) when its script is done and it decoded the expected
## ends, or when its session ended; the host waits for every file (up to the time limit), then
## compares each with view_of: the events as a prefix (the match goes on while the files are
## written) that reaches view_of's last MatchEnded, snapshots and voice as subsets, the §4.6
## invariants, the lurker and the refused bot. Its own bot (bot 1) it compares from the live client,
## exactly. Every bot adds its transport's rejects and its undecodable messages to its failures;
## only bot 1, the host's own in-process client, also counts a superseded LATEST message (a remote
## bot's real network may bunch two snapshots in one poll).

const ADDRESS := "127.0.0.1"
const USEC_PER_SECOND := 1000000
## The lurker's hello deadline is the run's time limit plus this; a remote bot waits this long past
## the time limit for the host to close.
const MARGIN_S := 10
const EXTRA_CLIENTS := 3
const PEERS_FILE := "peers"

## This process's bot number (PRIME_INSTANCE).
var instance := 1
var port := 0
var dir := ""
var session: HostSession
var game: Match
var lurker: BotWatcher
var refused: BotWatcher
## The command log written for a failed scenario, or "".
var replay_path := ""

var _start_usec := 0
var _invariants: ScenarioInvariants
var _leaks: LeakCheck
var _wrote_view := false
var _finished := false
var _known_peers := 0


func _init(bot_scenario: BotScenario, this_instance: int, on_port: int, out_dir: String) -> void:
	super(bot_scenario, ScenarioPeers.new())
	instance = this_instance
	port = on_port
	dir = out_dir
	ends_from_bots = instance != 1
	peers.refresh = _read_peers


func is_host() -> bool:
	return instance == 1


## Starts this instance's part; false with `failures` when it cannot.
func start(now: int) -> bool:
	var problems := scenario.problems()
	for problem: String in problems:
		failures.append("scenario: %s" % problem)
	if instance < 1 or instance > scenario.bots:
		failures.append("instance %d of a scenario of %d bots" % [instance, scenario.bots])
	if not OS.is_debug_build():
		failures.append("the bots run in debug builds only (ForceRole's kind, the observer)")
	if not failures.is_empty():
		return false
	now_usec = now
	_start_usec = now
	var bot := ScenarioBot.new(instance, 0, scenario.steps_of(instance), peers)
	bots.append(bot)
	if is_host():
		return _start_host(bot)
	if not bot.joins_late():
		_connect(bot)
	return true


## One frame at `now` (microseconds of the real clock).
func step(now: int) -> void:
	now_usec = now
	@warning_ignore("integer_division")
	tick_now = (now - _start_usec) * Ticks.RATE / USEC_PER_SECOND
	if is_host():
		session.step(now)
		if not session.is_running():
			failures.append(
				"the host session ended (%s): %s" % [session.end_reason, "; ".join(session.errors)]
			)
			_finished = true
			return
		lurker.poll()
		refused.poll()
		_read_peer_files()
	step_clients()
	var bot := bots[0]
	if is_host() or bot.joins_late() or _has_map():
		play_frame(tick_now)
	if not _wrote_view and (bot.gone or (bot.finished() and _ended()) or not failures.is_empty()):
		_write_view()
	if is_host():
		_finished = _host_done()
	elif _wrote_view:
		var client: BotClient = clients.get(bot.number)
		_finished = client == null or client.is_ended()
	if tick_now > Ticks.from_seconds(scenario.time_limit_s + (MARGIN_S if not is_host() else 0)):
		if not _ended() or not _wrote_view:
			_fail_time_limit()
		if not _wrote_view:
			_write_view()
		_finished = true


func done() -> bool:
	return _finished


## The host compares what every bot decoded with view_of, writes a failed scenario's command log
## and closes; a remote bot leaves. The failures of every bot are in `failures` on the host.
func finish() -> void:
	if is_host() and session != null:
		if session.is_running():
			_compare()
		if not failures.is_empty() and game != null:
			replay_path = ReplayFiles.write(game.command_log, dir)
		lurker.close()
		refused.close()
		session.close()
	for client: BotClient in clients.values():
		if not client.is_ended():
			client.leave()


func _start_host(bot: ScenarioBot) -> bool:
	if not scenario.steps_of(1).is_empty() and scenario.steps_of(1)[0] is StepJoin:
		failures.append("scenario: bot 1 is the host's own client, connected at the start")
		return false
	var world := FlatWorldQuery.new()
	var levels := MarkerReader.read_levels(scenario.mode, world)
	for error: String in levels.errors:
		failures.append("level: %s" % error)
	if not levels.errors.is_empty():
		return false
	var transport := EnetTransport.new(schema.kind_table())
	transport.bind_address = ADDRESS
	session = HostSession.new(transport, schema)
	session.replay_dir = ""
	session.hello_deadline_usec = ceili(scenario.time_limit_s + MARGIN_S) * USEC_PER_SECOND
	session.observer = _on_call
	var started := session.start_with(
		scenario.mode,
		world,
		levels.layouts,
		port,
		scenario.bots + EXTRA_CLIENTS,
		now_usec,
		scenario.session_seed
	)
	if not started:
		for error: String in session.errors:
			failures.append("host: %s" % error)
		return false
	bot.connected = true
	add_client(bot, session.own_client)
	lurker = BotWatcher.lurker(_joining(), schema)
	refused = BotWatcher.refused(_joining(), schema, session.content_hash)
	return true


func _join_host(bot: ScenarioBot) -> String:
	add_client(bot, _joining())
	return ""


func _joining() -> EnetTransport:
	var transport := EnetTransport.new(schema.kind_table())
	var joined := transport.join(ADDRESS, port)
	if joined != OK:
		failures.append("cannot join %s:%d: %s" % [ADDRESS, port, error_string(joined)])
	return transport


func _peer_known(bot: ScenarioBot) -> void:
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		failures.append("cannot create %s" % dir)
		return
	var file := FileAccess.open(dir.path_join("peer-%d" % bot.number), FileAccess.WRITE)
	if file == null:
		failures.append("cannot write %s" % dir.path_join("peer-%d" % bot.number))
		return
	file.store_string(str(bot.peer))
	file.close()


## The host reads the peer ids the other instances wrote, and writes the map when it grew.
func _read_peer_files() -> void:
	for number in range(2, scenario.bots + 1):
		if peers.has_bot(number):
			continue
		var path := dir.path_join("peer-%d" % number)
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		if text.is_valid_int():
			peers.set_peer(number, text.to_int())
	var known := peers.to_dict()
	if known.size() == _known_peers:
		return
	for number in range(1, scenario.bots + 1):
		var late := (
			not scenario.steps_of(number).is_empty() and scenario.steps_of(number)[0] is StepJoin
		)
		if not late and not known.has(number):
			return  # the first map holds every bot that joins at the start
	var lines := PackedStringArray()
	for number: int in known:
		lines.append("%d %d" % [number, known[number]])
	var file := FileAccess.open(dir.path_join(PEERS_FILE + ".part"), FileAccess.WRITE)
	if file == null:
		failures.append("cannot write the peers file in %s" % dir)
		return
	file.store_string("\n".join(lines))
	file.close()
	# A remote bot reading `peers` can block the rename on Windows: the next frame tries again.
	var part := dir.path_join(PEERS_FILE + ".part")
	if DirAccess.rename_absolute(part, dir.path_join(PEERS_FILE)) == OK:
		_known_peers = known.size()


## A remote bot plays once it has read bot 1's map.
func _has_map() -> bool:
	if not peers.has_bot(1):
		_read_peers(peers)
	return peers.has_bot(1)


## A remote bot reads the map bot 1 wrote (ScenarioPeers.refresh).
func _read_peers(map: ScenarioPeers) -> void:
	if is_host():
		return
	var path := dir.path_join(PEERS_FILE)
	if not FileAccess.file_exists(path):
		return
	for line: String in FileAccess.get_file_as_string(path).split("\n", false):
		var pair := line.split(" ")
		if pair.size() == 2 and pair[0].is_valid_int() and pair[1].is_valid_int():
			if pair[0].to_int() != instance:
				map.set_peer(pair[0].to_int(), pair[1].to_int())


func _write_view() -> void:
	_wrote_view = true
	var bot := bots[0]
	var client: BotClient = clients.get(bot.number)
	var view := client.view if client != null else DecodedView.new()
	# The host's own bot is counted in _compare, over its whole run.
	if client != null and not is_host():
		var label := "bot %d" % bot.number
		failures.append_array(
			LeakCheck.check_counters(
				label, bot.peer, client.transport(), client.bad_payloads, false
			)
		)
	if not ViewFile.write(dir, bot.number, bot.peer, view, failures):
		failures.append("cannot write the view file of bot %d" % bot.number)


## Every bot's view file is there (its script ended), or the time limit passed.
func _host_done() -> bool:
	if not _wrote_view or not failures.is_empty():
		return not failures.is_empty()
	for number in range(2, scenario.bots + 1):
		if not FileAccess.file_exists(ViewFile.path_of(dir, number)):
			return false
	return true


func _on_call(at_tick: int, command: MatchCommand, slice: Array[EmittedEvent]) -> void:
	if _invariants == null:
		game = session.game
		game.keep_history = true
		_invariants = ScenarioInvariants.new(game, scenario, peers)
		_leaks = LeakCheck.new(game)
	for problem: String in _invariants.check_call(command, slice):
		failures.append("invariant at tick %d: %s" % [at_tick, problem])
	for emitted: EmittedEvent in slice:
		if emitted.event.event_name() == MATCH_ENDED:
			ends.append(StringName(str(emitted.event.to_dict().get("side", ""))))
	if command == null:
		_leaks.record_tick(at_tick)


func _compare() -> void:
	if failures.is_empty() and ends != _expected_sides():
		failures.append("expected the ends %s, got %s" % [scenario.expected_ends, ends])
	for line: String in game.diagnostics:
		if line.begins_with("error:"):
			failures.append("match %s" % line)
	_leaks.set_seeds(_invariants.seeds())
	var views: Dictionary[String, DecodedView] = {}
	# The host's own bot, stepped in this frame after the session: exactly what it decoded so far.
	var own: BotClient = clients[1]
	failures.append_array(_leaks.check_bot("bot 1", bots[0].peer, own.view, false))
	failures.append_array(
		LeakCheck.check_counters("bot 1", bots[0].peer, own.transport(), own.bad_payloads, true)
	)
	views["bot 1"] = own.view
	for number in range(2, scenario.bots + 1):
		var file := ViewFile.read(dir, number)
		if file.is_empty():
			failures.append("bot %d wrote no view file" % number)
			continue
		for failure: String in file["failures"] as PackedStringArray:
			failures.append("bot %d: %s" % [number, failure])
		var peer: int = file["peer"]
		var view: DecodedView = file["view"]
		var label := "bot %d" % number
		failures.append_array(_leaks.check_bot(label, peer, view, true, true))
		if peer != 0:
			views[label] = view
	failures.append_array(_leaks.check_tasks(views))
	for watcher: BotWatcher in [lurker, refused]:
		failures.append_array(_leaks.check_watcher(watcher))
		failures.append_array(
			LeakCheck.check_counters(
				watcher.label, watcher.peer, watcher.transport, watcher.undecodable, false
			)
		)
