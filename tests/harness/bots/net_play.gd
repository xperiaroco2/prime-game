class_name NetPlay
extends ScenarioPlay
## The scenario steps played by network bots (ARCHITECTURE §4.6, §9.7): each bot is a BotClient
## (the ClientSession every client runs) and learns only from what it decoded, as (name, fields).
## Its mover is honest: it moves its position toward the target at the walk or sprint speed of the
## mode's PlayerRules, one client tick of travel per client tick, and its ClientSession claims it
## every client tick, counts its jumps and adopts every Correction. Its voice is synthetic: one
## frame per client tick holding its peer id and a counter (LeakCheck.voice_frame), so a listener
## checks that the relay changed no frame and named the right speaker.
##
## Bot 1 is the host's own client: it sends the setup's forced roles (one ForceRole per bot, on the
## debug kind, E17), once it knows the peer ids of every bot that joins at the start, then the
## setup's settings and map; a bot that joins later gets its ForceRole once its id is known.
##
## A runner owns the clock (now_usec), makes each bot's client (add_client) and calls play_frame()
## once per frame after the clients stepped. BotsRunner plays in one process over LoopbackHub;
## BotsEnet over ENet, one bot per process.

## The schema every bot and host uses: a debug build's, which has ForceRole's kind (E17).
var schema := WireSchema.game(true)
## Bot number -> its client.
var clients: Dictionary[int, BotClient] = {}
## The clock of the runner, in microseconds.
var now_usec := 0
## Count MatchEnded sides from what the bots decoded (over ENet a bot's own process has no
## observer); the one-process runner counts them from the host's slices instead.
var ends_from_bots := false

## Bot number -> the client tick of its last move (absent while it stands).
var _moved_tick: Dictionary[int, int] = {}
## Bot number -> the client tick of its last voice frame, and frames sent.
var _voice_tick: Dictionary[int, int] = {}
var _voice_count: Dictionary[int, int] = {}
var _facing_of: Dictionary[int, Vector3] = {}
var _snapshot_seen: Dictionary[int, int] = {}
## The bots whose ForceRole bot 1 sent; the settings went.
var _forced: Dictionary[int, bool] = {}
var _settings_sent := false


## Makes `bot`'s client on `transport` (not joined yet, or the host's own client).
func add_client(bot: ScenarioBot, transport: NetTransport) -> BotClient:
	var client := BotClient.new(transport, scenario.mode, schema)
	client.keep_history = true
	client.load_levels = false
	client.hold_load_ack = func() -> bool: return bot.current_step() is StepLoadAck
	client.event_received.connect(_on_event.bind(bot))
	transport.connected.connect(_on_connected.bind(bot))
	clients[bot.number] = client
	return client


## Steps every bot's client at now_usec, each poll a batch of the bot's events.
func step_clients() -> void:
	for bot: ScenarioBot in bots:
		var client: BotClient = clients.get(bot.number)
		if client == null or client.is_ended():
			continue
		bot.begin_batch()
		client.step(now_usec)
		if client.model.snapshot_tick != _snapshot_seen.get(bot.number, -1):
			_snapshot_seen[bot.number] = client.model.snapshot_tick
			bot.see(client.model.avatars)


## Every bot acts on what it decoded so far, at tick `at_tick` of the runner's clock, then speaks.
func play_frame(at_tick: int) -> void:
	for bot: ScenarioBot in bots:
		if bot.gone or not failures.is_empty():
			continue
		var client: BotClient = clients.get(bot.number)
		if client != null and client.is_ended():
			_lost(bot, client, at_tick)
			continue
		_act(bot, at_tick)
		_speak(bot)


## Its session ended (the host disconnected it, closed, or refused its join): it acts no more, but a
## Join step first reads the Rejected that refused it.
func _lost(bot: ScenarioBot, client: BotClient, at_tick: int) -> void:
	if not bot.joined:
		if client.end_reason == ClientSession.CONNECT_FAILED:
			tick_now = at_tick
			_fail_step(bot, "the host refuses new connections (connect_failed)")
		else:
			_act(bot, at_tick)
	bot.gone = true


func _on_connected(own_id: int, bot: ScenarioBot) -> void:
	bot.peer = own_id
	peers.set_peer(bot.number, own_id)
	_peer_known(bot)


## A bot's peer id became known (ENet: it is written for the other instances).
func _peer_known(_bot: ScenarioBot) -> void:
	pass


func _on_event(event_name: StringName, fields: Dictionary, bot: ScenarioBot) -> void:
	if bot.gone:
		return
	var problem := bot.receive(event_name, fields)
	if not problem.is_empty():
		_fail_step(bot, problem)
	if event_name == &"Rejected" and bot.joined and fields["seq"] != bot.sent_seq:
		_fail_step(bot, "Rejected (%s) for intent %d" % [fields["reason"], fields["seq"]])
	if ends_from_bots and event_name == MATCH_ENDED:
		ends.append(StringName(str(fields["side"])))


func _before_steps(bot: ScenarioBot) -> void:
	if bot.load_ack_due:
		# Its session acknowledged that LoadMatch at once (load_levels off).
		bot.load_ack_due = false
		bot.auto_acked_match = bot.match_id
	if bot.number == 1:
		_send_setup(bot)


## Bot 1 sends the setup's ForceRoles (each once its bot's peer id is known; the first ones once
## every bot that joins at the start is known), then the settings and map, once.
func _send_setup(host: ScenarioBot) -> void:
	if not host.connected or host.peer == 0:
		return
	for bot: ScenarioBot in bots:
		if not bot.joins_late() and not peers.has_bot(bot.number):
			return
	var client: BotClient = clients[1]
	for bot: int in scenario.forced_roles:
		if _forced.has(bot) or not peers.has_bot(bot):
			continue
		_forced[bot] = true
		if client.force_role(peers.peer_of(bot), String(scenario.forced_roles[bot])) < 0:
			_fail_step(host, "could not send ForceRole for bot %d" % bot)
	if _settings_sent:
		return
	_settings_sent = true
	if scenario.settings.is_empty() and scenario.map.is_empty():
		return
	var values := {}
	for id: StringName in scenario.settings:
		values[String(id)] = scenario.settings[id]
	var args := {"settings": values}
	if not scenario.map.is_empty():
		args["map"] = scenario.map
	if client.send_intent(Intents.CHANGE_SETTINGS, args) < 0:
		_fail_step(host, "could not send the setup's ChangeSettings")


func _send(bot: ScenarioBot, kind: StringName, args: Dictionary) -> void:
	bot.sent_seq = clients[bot.number].send_intent(kind, args)
	if bot.sent_seq < 0:
		_fail_step(bot, "could not send %s" % kind)


func _connect(bot: ScenarioBot) -> String:
	bot.connected = true
	# Hello's seq is 0: a Rejected of the join answers it.
	bot.sent_seq = 0
	return _join_host(bot)


## Joins `bot`'s client to the host (a late Join step): its Hello follows on `connected`. Returns
## why it cannot, or "".
func _join_host(_bot: ScenarioBot) -> String:
	return "this runner joins no bot late"


func _travel_ticks(bot: ScenarioBot) -> int:
	var now_tick := clients[bot.number].client_tick(now_usec)
	var last: int = _moved_tick.get(bot.number, now_tick - 1)
	_moved_tick[bot.number] = now_tick
	return now_tick - last


func _claim(bot: ScenarioBot, to: Vector3, velocity: Vector3, sprint: bool) -> void:
	var facing := velocity.normalized() if not velocity.is_zero_approx() else Vector3.FORWARD
	_facing_of[bot.number] = facing
	clients[bot.number].set_motion(to, velocity, facing, sprint, true, true)
	bot.position = to


func _stand(bot: ScenarioBot) -> void:
	var client: BotClient = clients.get(bot.number)
	if client == null:
		return
	_moved_tick.erase(bot.number)
	var facing: Vector3 = _facing_of.get(bot.number, Vector3.FORWARD)
	client.set_motion(bot.position, Vector3.ZERO, facing, false, false, true)


func _jump(bot: ScenarioBot) -> void:
	bot.jumps += 1
	clients[bot.number].count_jump()


func _leave(bot: ScenarioBot) -> void:
	clients[bot.number].leave()


func _answer_load(bot: ScenarioBot, match_id: int, skip: bool) -> void:
	if not skip:
		clients[bot.number].send_load_ack(match_id)


## One synthetic voice frame per client tick, once the bot is a player.
func _speak(bot: ScenarioBot) -> void:
	var client: BotClient = clients.get(bot.number)
	if bot.gone or not bot.joined or client == null or client.is_ended():
		return
	var now_tick := client.client_tick(now_usec)
	if now_tick <= _voice_tick.get(bot.number, -1):
		return
	_voice_tick[bot.number] = now_tick
	var counter: int = _voice_count.get(bot.number, 0)
	if client.send_voice(LeakCheck.voice_frame(bot.peer, counter)) == OK:
		_voice_count[bot.number] = counter + 1
