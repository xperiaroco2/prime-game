class_name PerfRun
extends NetPlay
## One perf run (ARCHITECTURE §9.7, #187; `tools\run.cmd perf`): a HostSession and its bots play a
## PerfScenario, measured from the harness side. Over a LoopbackHub in one process on a simulated
## clock (one 1/60 s frame per frame(), so the match is the same every run) or, with `enet`, over
## ENet on 127.0.0.1 on the real clock, the host and every bot's client still in one process.
## Bot 1 is the host's own client, as in the game; the other bots are BotClients.
##
## Measured, without changing what the host does:
## - the host step: Time.get_ticks_usec() around HostSession.step(), kept for the steps that ran at
##   least one host tick (a frame between two ticks only polls);
## - what the host's transport sent and received per remote peer and tick (WireMeter, through
##   MeteredLoopback or MeteredEnet and packet_received);
## - the events per host tick: the slices HostSession's observer (debug builds) hands over, counted
##   and nothing else, so the host's Match keeps keep_history off, as in the game;
## - with sample() once per physics frame (PerfMain): Performance's TIME_PHYSICS_PROCESS, which
##   the engine sets once a second of real time to the longest physics frame of that second (so it
##   is kept once a second), and MEMORY_STATIC; both
##   MEMORY_STATIC, the whole process's, the bots' clients included.
## Fails on a step's failure, the session ending, an end other than the scenario's, or the host
## counting a message over budget or a rejected packet: honest bots trip neither.

const ADDRESS := "127.0.0.1"
const LOOPBACK_PORT := 7400
## One frame of the simulated clock: 60 steps per simulated second, as BotsRunner.
const FRAME_USEC := 16667
const START_USEC := 1000000
const USEC_PER_SECOND := 1000000.0
const MSEC_PER_SECOND := 1000
## The transport's room besides the bots.
const EXTRA_CLIENTS := 1

var enet := false
var port := LOOPBACK_PORT
var session: HostSession
var host_transport: NetTransport
var meter: WireMeter
var hub := LoopbackHub.new()
var frames_run := 0
## Host step durations in microseconds, of the steps that ran at least one host tick.
var tick_usec := PackedInt64Array()
## TIME_PHYSICS_PROCESS once per second of real time, in microseconds: the longest physics frame
## of the second before.
var physics_usec := PackedInt64Array()
var memory_static_max := 0
var memory_static_end := 0

## Host tick -> events in the slices of that tick's Match calls.
var _events: Dictionary[int, int] = {}
var _finished := false
var _sampled_ms := -1


func _init(bot_scenario: BotScenario, over_enet := false, on_port := 0) -> void:
	super(bot_scenario, ScenarioPeers.new())
	enet = over_enet
	if on_port > 0:
		port = on_port
	meter = WireMeter.new(schema)


## Starts the host and connects every bot; false with `failures` when it cannot.
func start() -> bool:
	for problem: String in scenario.problems():
		failures.append("scenario: %s" % problem)
	if not OS.is_debug_build():
		failures.append("perf runs in debug builds only (ForceClock, the observer)")
	if not failures.is_empty():
		return false
	var world := FlatWorldQuery.new()
	var levels := MarkerReader.read_levels(scenario.mode, world)
	for error: String in levels.errors:
		failures.append("level: %s" % error)
	if not levels.errors.is_empty():
		return false
	if enet:
		var metered := MeteredEnet.new(schema.kind_table(), meter)
		metered.bind_address = ADDRESS
		host_transport = metered
	else:
		host_transport = MeteredLoopback.new(schema.kind_table(), hub, meter)
	host_transport.packet_received.connect(meter.received)
	session = HostSession.new(host_transport, schema)
	session.replay_dir = ""
	session.observer = _on_call
	now_usec = Time.get_ticks_usec() if enet else START_USEC
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
	for number in range(1, scenario.bots + 1):
		bots.append(ScenarioBot.new(number, 0, scenario.steps_of(number), peers))
	bots[0].connected = true
	add_client(bots[0], session.own_client)
	for bot: ScenarioBot in bots.slice(1):
		_connect(bot)
	return true


## One frame: the host steps (timed), then every client, then every bot acts.
func frame() -> void:
	now_usec = Time.get_ticks_usec() if enet else now_usec + FRAME_USEC
	var due := session.tick_of(now_usec)
	meter.tick = due
	var before := session.game.ticked_through()
	var began := Time.get_ticks_usec()
	session.step(now_usec)
	var took := Time.get_ticks_usec() - began
	frames_run += 1
	if not session.is_running():
		failures.append(
			"the host session ended (%s): %s" % [session.end_reason, "; ".join(session.errors)]
		)
		_finished = true
		return
	if session.game.ticked_through() > before:
		tick_usec.append(took)
	step_clients()
	tick_now = due
	play_frame(tick_now)
	if not failures.is_empty() or _ended():
		_finished = true
	elif tick_now > Ticks.from_seconds(scenario.time_limit_s):
		_fail_time_limit()
		_finished = true


## Performance's monitors; once per physics frame.
func sample() -> void:
	var now_ms := Time.get_ticks_msec()
	if _sampled_ms < 0:
		_sampled_ms = now_ms
	elif now_ms - _sampled_ms >= MSEC_PER_SECOND:
		_sampled_ms = now_ms
		var physics := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		physics_usec.append(roundi(physics * USEC_PER_SECOND))
	memory_static_end = roundi(Performance.get_monitor(Performance.MEMORY_STATIC))
	memory_static_max = maxi(memory_static_max, memory_static_end)


func done() -> bool:
	return _finished


## Checks the ends and the host's counters, then every bot leaves and the session closes.
func finish() -> void:
	if session != null and session.is_running():
		if failures.is_empty() and ends != _expected_sides():
			failures.append("expected the ends %s, got %s" % [scenario.expected_ends, ends])
		if session.over_budget != 0:
			failures.append("the host counted %d messages over budget" % session.over_budget)
		if host_transport.rejects.total() != 0:
			failures.append(
				"the host's transport rejected %d packets" % host_transport.rejects.total()
			)
	for client: BotClient in clients.values():
		if not client.is_ended():
			client.leave()
	if session != null:
		session.close()


## The run's numbers for `tools\run.cmd perf`, which summarises them (tools/runner/perf.py).
func to_dict() -> Dictionary:
	var last := -1
	for at: int in _events:
		last = maxi(last, at)
	var events: Array[int] = []
	for at in range(0, last + 1):
		var count: int = _events.get(at, 0)
		events.append(count)
	var kinds := schema.kind_table()
	var sides: Array[String] = []
	for side: StringName in ends:
		sides.append(String(side))
	var result := {
		"transport": "enet" if enet else "loopback",
		"bots": scenario.bots,
		"seconds": scenario.clock_s,
		"seed": scenario.session_seed,
		"ticks_per_second": Ticks.RATE,
		"frames": frames_run,
		"host_ticks":
		session.game.ticked_through() if session != null and session.game != null else 0,
		"tick_usec": Array(tick_usec),
		"physics_usec": Array(physics_usec),
		"events_per_tick": events,
		"memory_static": {"end": memory_static_end, "max": memory_static_max},
		"budgets":
		{
			"snapshot_payload_cap": kinds.payload_cap(schema.kind_of(HostSession.SNAPSHOT)),
			"voice_down_payload_cap": kinds.payload_cap(schema.kind_of(&"VoiceDown")),
			"frame_header_bytes": NetFrame.HEADER_BYTES,
			"peer_bytes_per_second": PeerBudget.BYTES_PER_SECOND,
			"peer_voice_frames_per_second": PeerBudget.VOICE_FRAMES_PER_SECOND,
		},
		"failures": Array(failures),
		"ends": sides,
	}
	result.merge(meter.to_dict())
	return result


func _join_host(bot: ScenarioBot) -> String:
	var transport: NetTransport
	if enet:
		var client := EnetTransport.new(schema.kind_table())
		var joined := client.join(ADDRESS, port)
		if joined != OK:
			failures.append("cannot join %s:%d: %s" % [ADDRESS, port, error_string(joined)])
		transport = client
	else:
		transport = LoopbackTransport.new(schema.kind_table(), hub)
		transport.join("loopback", port)
	add_client(bot, transport)
	return ""


## HostSession's observer: counts each call's events for its tick, and the ends.
func _on_call(at_tick: int, _command: MatchCommand, slice: Array[EmittedEvent]) -> void:
	var had: int = _events.get(at_tick, 0)
	_events[at_tick] = had + slice.size()
	for emitted: EmittedEvent in slice:
		if emitted.event.event_name() == MATCH_ENDED:
			ends.append(StringName(str(emitted.event.to_dict().get("side", ""))))
