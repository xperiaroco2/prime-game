class_name ScenarioRunner
extends ScenarioPlay
## The core runner of bot scenarios (ARCHITECTURE §9.7, stage 2j): plays a BotScenario's steps
## (ScenarioPlay) by driving Match directly, as server/ would. Each host tick every bot acts on what
## it received so far (its script's current step becomes intents, stamped with the tick), the
## commands are applied in bot order, the tick runs, and each emitted event reaches exactly its
## recorded recipients: a bot sees only its peer's `view_of`, as (name, to_dict()). The geometry is
## a flat fake world (FlatWorldQuery, one floor at y = 0), and the levels are the mode's real ones,
## read by server/'s MarkerReader. Bot 1 is peer 1, bot i is ScenarioPeers.PEER_BASE + i.
##
## Always asserted besides the steps' failures: the expected ends; no match error in
## `Match.diagnostics` (every `push_error` of core/ is one); the §5 invariants on every bot's stream
## (ScenarioInvariants); and that each bot received exactly its peer's `view_of` events.
##
## Server-side behaviour it stands in for (`_queue`, `_deliver`, `_carry_out`): joins at tick 0
## (PeerConnected, then Hello) unless a Join step says later; the setup's forced roles, then its
## settings and map in one ChangeSettings from the host's bot right after the joins (bot 1 joins at
## the start then); a LoadAck at once for every LoadMatch that no LoadAck step answers; RefuseJoins
## and AllowJoins; DisconnectPeer ends that bot, and its PeerLeft follows on the next tick.

var game: Match
var ticks_run := 0

var _invariants: ScenarioInvariants
var _commands: Array[MatchCommand] = []
var _to_leave: Array[int] = []
var _refusing := false


func _init(bot_scenario: BotScenario) -> void:
	super(bot_scenario, ScenarioPeers.core(bot_scenario.bots))


## Plays `bot_scenario` to its end; see `failures`.
static func play(bot_scenario: BotScenario) -> ScenarioRunner:
	var runner := ScenarioRunner.new(bot_scenario)
	runner.run()
	return runner


func run() -> void:
	var problems := scenario.problems()
	for problem: String in problems:
		failures.append("scenario: %s" % problem)
	if not problems.is_empty():
		return
	var world := FlatWorldQuery.new()
	var levels := MarkerReader.read_levels(scenario.mode, world)
	for error: String in levels.errors:
		failures.append("level: %s" % error)
	if not levels.errors.is_empty():
		return
	game = Match.new(scenario.mode, scenario.session_seed, world, levels.layouts)
	for refusal: String in game.refusals:
		failures.append("mode: %s" % refusal)
	if not game.refusals.is_empty():
		return
	_invariants = ScenarioInvariants.new(game, scenario, peers)
	for number in range(1, scenario.bots + 1):
		bots.append(
			ScenarioBot.new(number, peers.peer_of(number), scenario.steps_of(number), peers)
		)
	if not game.start(0):
		failures.append("the match did not start")
		return
	_deliver()
	var limit := Ticks.from_seconds(scenario.time_limit_s)
	for at_tick in range(0, limit + 1):
		_run_tick(at_tick)
		ticks_run = at_tick + 1
		if not failures.is_empty() or _ended():
			break
	tick_now = game.ticked_through() + 1
	if failures.is_empty() and not _ended():
		_fail_time_limit()
	if failures.is_empty():
		_check_after()


func _run_tick(at_tick: int) -> void:
	_commands.clear()
	for peer: int in _to_leave:
		_queue(Intents.PEER_LEFT, peer)
	_to_leave.clear()
	if at_tick == 0:
		_join_at_start()
	for bot: ScenarioBot in bots:
		if not bot.gone and failures.is_empty():
			_act(bot, at_tick)
	for command: MatchCommand in _commands:
		_invariants.sender = command.peer
		if not game.apply(command):
			failures.append("tick %d: %s was not applied" % [at_tick, command.kind])
		_deliver()
	_invariants.sender = 0
	game.tick(at_tick)
	_deliver()
	for problem: String in _invariants.check_tick():
		failures.append("tick %d: %s" % [at_tick, problem])
	for bot: ScenarioBot in bots:
		if not bot.gone and bot.joined:
			bot.see(game.snapshot_for(bot.peer).get("avatars", {}) as Dictionary)


## Every bot without a Join step connects and says Hello; then the host's bot sends the setup's
## settings and map.
func _join_at_start() -> void:
	for bot: ScenarioBot in bots:
		if not bot.joins_late():
			_connect(bot)
	# As server/'s debug path would: a ForceRole per forced bot, by its peer id, in the lobby.
	for bot: int in scenario.forced_roles:
		_queue(Intents.FORCE_ROLE, peers.peer_of(bot), {"role": String(scenario.forced_roles[bot])})
	if scenario.settings.is_empty() and scenario.map.is_empty():
		return
	var host := bots[0]
	var values := {}
	for id: StringName in scenario.settings:
		values[String(id)] = scenario.settings[id]
	var args := {"settings": values}
	if not scenario.map.is_empty():
		args["map"] = scenario.map
	_queue(Intents.CHANGE_SETTINGS, host.peer, args, host.next_seq())


func _connect(bot: ScenarioBot) -> String:
	if _refusing:
		return "the host refuses new connections (Loading, Round or End)"
	bot.connected = true
	_queue(Intents.PEER_CONNECTED, bot.peer)
	bot.sent_seq = bot.next_seq()
	_queue(
		Intents.HELLO,
		bot.peer,
		# The bot's own copy of the content is the host's: one process, one content/.
		{
			"name": "bot%d" % bot.number,
			"version": JoinRules.PROTOCOL_VERSION,
			"content": game.content_hash,
		},
		bot.sent_seq
	)
	return ""


func _before_steps(bot: ScenarioBot) -> void:
	if bot.load_ack_due and bot.joined:
		bot.load_ack_due = false
		bot.auto_acked_match = bot.match_id
		_queue(Intents.LOAD_ACK, bot.peer, {"match_id": bot.match_id}, bot.next_seq())


func _answer_load(bot: ScenarioBot, match_id: int, skip: bool) -> void:
	if not skip:
		_send(bot, Intents.LOAD_ACK, {"match_id": match_id})


func _jump(bot: ScenarioBot) -> void:
	bot.jumps += 1
	_claim(bot, bot.position, Vector3.ZERO, false)


func _leave(bot: ScenarioBot) -> void:
	_queue(Intents.PEER_LEFT, bot.peer)


## An honest MoveClaim of the bot to `to`, which it then takes as its position, with its jump
## count in the epoch: one host tick of travel per tick, client ticks rising by one.
func _claim(bot: ScenarioBot, to: Vector3, velocity: Vector3, sprint: bool) -> void:
	var facing := velocity.normalized() if not velocity.is_zero_approx() else Vector3.FORWARD
	var args := {
		"epoch": bot.epoch,
		"client_tick": bot.next_client_tick(),
		"position": to,
		"velocity": velocity,
		"facing": facing,
		"sprint": sprint,
		"moving": not velocity.is_zero_approx(),
		"jumps": bot.jumps,
		"on_floor": true,
	}
	_queue(Intents.MOVE_CLAIM, bot.peer, args, bot.next_seq())
	bot.position = to


func _send(bot: ScenarioBot, kind: StringName, args: Dictionary) -> void:
	bot.sent_seq = bot.next_seq()
	_queue(kind, bot.peer, args, bot.sent_seq)


func _queue(kind: StringName, peer: int, args: Dictionary = {}, seq: int = 0) -> void:
	_commands.append(MatchCommand.new(kind, peer, game.ticked_through() + 1, args, seq))


## Hands the events emitted since the last call to their recipients, as server/ would.
func _deliver() -> void:
	var batch := game.take_outbox()
	for emitted: EmittedEvent in batch:
		for problem: String in _invariants.check_event(emitted):
			failures.append("invariant: %s" % problem)
		if emitted.is_directive:
			_carry_out(emitted.event)
			continue
		if emitted.event.event_name() == MATCH_ENDED:
			ends.append(StringName(str(emitted.event.to_dict().get("side", ""))))
		for peer: int in emitted.recipients:
			var bot := _bot_of(peer)
			if bot == null:
				continue
			var problem := bot.receive(emitted.event.event_name(), emitted.event.to_dict())
			if not problem.is_empty():
				_fail_step(bot, problem)
			var rejected := emitted.event as RejectedEvent
			if rejected != null and rejected.seq != bot.sent_seq:
				_fail_step(bot, "Rejected (%s) for intent %d" % [rejected.reason, rejected.seq])


func _carry_out(directive: MatchEvent) -> void:
	if directive is RefuseJoinsEvent:
		_refusing = true
	elif directive is AllowJoinsEvent:
		_refusing = false
	elif directive is DisconnectPeerEvent:
		var peer := (directive as DisconnectPeerEvent).peer
		var bot := _bot_of(peer)
		if bot != null and not bot.gone:
			_disconnected(bot, tick_now)
			_to_leave.append(peer)


func _bot_of(peer: int) -> ScenarioBot:
	for bot: ScenarioBot in bots:
		if bot.peer == peer:
			return bot
	return null


func _check_after() -> void:
	if ends != _expected_sides():
		failures.append("expected the ends %s, got %s" % [scenario.expected_ends, ends])
	for line: String in game.diagnostics:
		if line.begins_with("error:"):
			failures.append("match %s" % line)
	for bot: ScenarioBot in bots:
		var view := game.view_of(bot.peer).events
		var received := bot.events
		var equal := view.size() == received.size()
		for i in mini(view.size(), received.size()):
			if not equal:
				break
			equal = (
				received[i].name == view[i].event_name() and received[i].fields == view[i].to_dict()
			)
		if not equal:
			failures.append(
				(
					"bot %d received %d events, but view_of(%d) holds %d"
					% [bot.number, received.size(), bot.peer, view.size()]
				)
			)
