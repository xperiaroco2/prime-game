class_name BotsRunner
extends NetPlay
## The one-process bots runner (ARCHITECTURE §4.6, §9.7; E12): plays a BotScenario through the
## network layers, in one process over a LoopbackHub, stepped by a simulated clock (60 steps per
## simulated second) as fast as the machine runs, so a long scenario takes seconds and runs the same
## every time. A HostSession hosts on the hub, with its match's keep_history on; bot 1 is its own
## client, the other bots are BotClients on loopback clients, and LoopbackHub hands out their peer
## ids (this runner's ScenarioPeers). Every scenario also runs a lurker and a refused bot
## (BotWatcher), with the hello deadline raised past the run for the lurker.
##
## Asserted: the steps (ScenarioPlay's failures); ScenarioInvariants per Match call, through
## HostSession's observer (§4.5); the expected ends; no match error; and the leak test (LeakCheck)
## for every bot, the lurker and the refused bot, with what only one process can promise: every
## speaker's voice seqs without a gap, and no packet rejected, undecoded or superseded on the LATEST
## lane (one snapshot per step and one poll per step, so a snapshot sent before a bot's own in the
## same step cannot hide); and on the host, no message over budget and no rejected packet. Each
## frame: the host steps, then every client, then every bot acts on what it decoded.

const PORT := 7400
## One frame of the simulated clock: 60 steps per simulated second.
const FRAME_USEC := 16667
const START_USEC := 1000000
const USEC_PER_SECOND := 1000000
## The lurker's hello deadline is the run's time limit plus this.
const LURKER_MARGIN_S := 10
## The transport's room besides the bots: the lurker, the refused bot and one spare.
const EXTRA_CLIENTS := 3

var session: HostSession
var game: Match
var hub := LoopbackHub.new()
## The host's transport.
var host_transport: NetTransport
## The port the host listens on (the hub's, or ENet's for the chaos run's ENet variant).
var port := PORT
## One process over the loopback: no client may count a superseded LATEST message (one snapshot
## per step, one poll per step) and every speaker's voice seqs run without a gap. The chaos run's
## ENet variant clears it: a real network may bunch, drop and reorder.
var one_process := true
var lurker: BotWatcher
var refused: BotWatcher
var frames_run := 0
## Where each bot's view file and a failed scenario's command log go; empty writes none.
var out_dir := ""
## The command log written for a failed scenario, or "".
var replay_path := ""

var _invariants: ScenarioInvariants
var _leaks: LeakCheck


func _init(bot_scenario: BotScenario) -> void:
	super(bot_scenario, ScenarioPeers.new())


## Plays `bot_scenario` to its end; see `failures`. With `out`, writes the view files there, and a
## failed scenario's command log.
static func play(bot_scenario: BotScenario, out := "") -> BotsRunner:
	var runner := BotsRunner.new(bot_scenario)
	runner.out_dir = out
	runner.run()
	runner.close()
	return runner


func run() -> void:
	var problems := scenario.problems()
	for problem: String in problems:
		failures.append("scenario: %s" % problem)
	if not problems.is_empty():
		return
	if not OS.is_debug_build():
		failures.append("the bots run in debug builds only (ForceRole's kind, the observer)")
		return
	if not scenario.steps_of(1).is_empty() and scenario.steps_of(1)[0] is StepJoin:
		failures.append("scenario: bot 1 is the host's own client, connected at the start")
		return
	var world := FlatWorldQuery.new()
	var levels := MarkerReader.read_levels(scenario.mode, world)
	for error: String in levels.errors:
		failures.append("level: %s" % error)
	if not levels.errors.is_empty():
		return
	host_transport = _make_host_transport()
	session = HostSession.new(host_transport, schema)
	session.replay_dir = ""
	session.hello_deadline_usec = (ceili(scenario.time_limit_s + LURKER_MARGIN_S) * USEC_PER_SECOND)
	session.observer = _on_call
	now_usec = START_USEC
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
		return
	_join_everyone()
	_play()
	if failures.is_empty():
		_check_after()
	_write_files()


## Leaves every client and closes the session.
func close() -> void:
	for client: BotClient in clients.values():
		if not client.is_ended():
			client.leave()
	for watcher: BotWatcher in [lurker, refused]:
		if watcher != null:
			watcher.close()
	if session != null:
		session.close()


func _join_everyone() -> void:
	for number in range(1, scenario.bots + 1):
		bots.append(ScenarioBot.new(number, 0, scenario.steps_of(number), peers))
	bots[0].connected = true
	add_client(bots[0], session.own_client)
	for bot: ScenarioBot in bots.slice(1):
		if not bot.joins_late():
			_connect(bot)
	lurker = BotWatcher.lurker(_joining(), schema)
	refused = BotWatcher.refused(_joining(), schema, session.content_hash)


func _play() -> void:
	var limit := ceili(scenario.time_limit_s * USEC_PER_SECOND / FRAME_USEC)
	for frame in limit:
		now_usec += FRAME_USEC
		session.step(now_usec)
		if not session.is_running():
			failures.append(
				"the host session ended (%s): %s" % [session.end_reason, "; ".join(session.errors)]
			)
			return
		_after_host_step()
		step_clients()
		lurker.poll()
		refused.poll()
		tick_now = session.tick_of(now_usec)
		play_frame(tick_now)
		frames_run = frame + 1
		if not failures.is_empty() or _ended():
			return
	_fail_time_limit()


func _join_host(bot: ScenarioBot) -> String:
	add_client(bot, _joining())
	return ""


## A loopback client joining the host (its id comes with `connected`).
func _joining() -> NetTransport:
	var transport := LoopbackTransport.new(schema.kind_table(), hub)
	transport.join("loopback", port)
	return transport


## The host's transport, not hosting yet: a loopback on the hub.
func _make_host_transport() -> NetTransport:
	return LoopbackTransport.new(schema.kind_table(), hub)


## Right after each host step, before the clients step (the chaos run's hook).
func _after_host_step() -> void:
	pass


## HostSession's observer: after every Match call, before its slice is delivered.
func _on_call(at_tick: int, command: MatchCommand, slice: Array[EmittedEvent]) -> void:
	if _invariants == null:
		# The start's call: the match exists, no tick has run yet.
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


func _check_after() -> void:
	if ends != _expected_sides():
		failures.append("expected the ends %s, got %s" % [scenario.expected_ends, ends])
	for line: String in game.diagnostics:
		if line.begins_with("error:"):
			failures.append("match %s" % line)
	_leaks.set_seeds(_invariants.seeds())
	var views: Dictionary[String, DecodedView] = {}
	for bot: ScenarioBot in bots:
		var client: BotClient = clients.get(bot.number)
		if client == null:
			continue
		var label := "bot %d" % bot.number
		failures.append_array(_leaks.check_bot(label, bot.peer, client.view, bot.gone))
		failures.append_array(
			LeakCheck.check_counters(
				label, bot.peer, client.transport(), client.bad_payloads, one_process
			)
		)
		if bot.peer == 0:
			continue
		if one_process:
			failures.append_array(_leaks.check_voice_streams(label, bot.peer, client.view))
		views[label] = client.view
	failures.append_array(_leaks.check_tasks(views))
	for watcher: BotWatcher in [lurker, refused]:
		failures.append_array(_leaks.check_watcher(watcher))
		failures.append_array(
			LeakCheck.check_counters(
				watcher.label, watcher.peer, watcher.transport, watcher.undecodable, one_process
			)
		)
	failures.append_array(host_problems())


## Honest bots trip no host budget and send nothing the host's transport rejects.
func host_problems() -> PackedStringArray:
	var found := PackedStringArray()
	if session.over_budget != 0:
		found.append("the host counted %d messages over budget" % session.over_budget)
	if host_transport.rejects.total() != 0:
		found.append("the host's transport rejected %d packets" % host_transport.rejects.total())
	return found


func _write_files() -> void:
	if out_dir.is_empty():
		return
	for bot: ScenarioBot in bots:
		var client: BotClient = clients.get(bot.number)
		if client != null:
			ViewFile.write(out_dir, bot.number, bot.peer, client.view, failures)
	if not failures.is_empty() and game != null:
		replay_path = ReplayFiles.write(game.command_log, out_dir)
