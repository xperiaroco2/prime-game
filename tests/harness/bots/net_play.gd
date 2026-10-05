class_name NetPlay
extends ScenarioPlay
## The scenario steps played by network bots (ARCHITECTURE §4.6, §9.7): each bot is a BotClient
## (the ClientSession every client runs) and learns only from what it decoded, as (name, fields).
## Its mover is honest: it moves its position toward the target at the walk or sprint speed of the
## mode's PlayerRules, one client tick of travel per client tick, and its ClientSession claims it
## every client tick, counts its jumps and adopts every Correction. It sprints while its own
## PredictedStamina, settled by its claims and following its SelfStatus as a player's controller
## does, says the next claim would be in the sprint state: a SelfStatus answers a claim some ticks
## old, and a bot that sprinted on its `sprint_available` would claim a sprint tick its stamina no
## longer pays for, which the host corrects (#155). Its voice is synthetic: one frame per 20 ms of
## the runner's clock, in talk spurts unless the scenario says continuously (BotVoice), each
## holding its peer id and a counter (LeakCheck.voice_frame), so a listener checks that the relay
## changed no frame and named the right speaker. It talks in every phase and life state, like a
## modified client: the host must route none of it where nobody hears it (§6); only a Talk step
## silences it (M5-4's voice_load).
##
## Bot 1 is the host's own client: it sends the setup's forced roles (one ForceRole per bot, on the
## debug kind, E17), once it knows the peer ids of every bot that joins at the start, then the
## setup's ForceClock (clock_s), settings and map; a bot that joins later gets its ForceRole once
## its id is known.
##
## A runner owns the clock (now_usec), makes each bot's client (add_client) and calls play_frame()
## once per frame after the clients stepped. BotsRunner plays in one process over LoopbackHub;
## BotsEnet over ENet, one bot per process.
##
## The start over ENet (#284, #318), shared by BotsEnet, ChaosRun's ENet variant and the playcheck
## bots: a bot acts only once its lobby is full (_lobby_full), and a bot that joins at the start and
## whose join went unanswered joins again (_join_again).

## A join that failed this long or more after it started went unanswered: half of
## EnetTransport.JOIN_TIMEOUT_MS, in microseconds (a frame's clock is read before its poll). A
## sooner `connect_failed` is a refusal.
const UNANSWERED_USEC := EnetTransport.JOIN_TIMEOUT_MS * 500
## Over WebRTC a join can also end at once because the host's room is not up yet (its process
## starts later, or its signalling has not opened the room): the bot joins again this long after.
const ROOM_RETRY_USEC := 500000
## The joins that end for no answer (ENet's connect_failed), and the ones that end because the
## room is not up yet (WebRTC). WebRTC's host_unreachable is no such case: the service answered and
## the connection never opened, a transport fault the run must not ride out.
const UNANSWERED: Array[StringName] = [ClientSession.CONNECT_FAILED]
const ROOM_NOT_UP: Array[StringName] = [
	NetTransport.JOIN_NO_ROOM, NetTransport.JOIN_SERVICE_UNREACHABLE
]

## The schema every bot and host uses: a debug build's, which has ForceRole's kind (E17).
var schema := WireSchema.game(true)
## Bot number -> its client.
var clients: Dictionary[int, BotClient] = {}
## The clock of the runner, in microseconds.
var now_usec := 0
## Count MatchEnded sides from what the bots decoded (over ENet a bot's own process has no
## observer); the one-process runner counts them from the host's slices instead.
var ends_from_bots := false
## Each frame the clients poll (step_clients), the bots act and move (play_frame), and only then do
## the clients claim (claim_clients): a claim covers the client ticks since the last one and carries
## the travel of exactly those ticks, also after a stall of the process (#284). On in BotsRunner
## and BotsEnet, and so in ChaosRun (a BotsRunner). Off (the perf and playcheck runners), a client
## claims as it polls, before the bot moves, so the bot moves one client tick at most per frame: a
## stall slows it down.
var claims_after_moves := false

## Bot number -> the client tick of its last move: kept by _stand only in the client tick of that
## move, and dropped while the bot is dead, so the first walk after standing or a respawn covers one
## client tick.
var _moved_tick: Dictionary[int, int] = {}
## Bot number -> the last 20 ms frame of the runner's clock its voice went through, and the frames
## it sent.
var _voice_frame: Dictionary[int, int] = {}
var _voice_count: Dictionary[int, int] = {}
var _facing_of: Dictionary[int, Vector3] = {}
var _snapshot_seen: Dictionary[int, int] = {}
## The bots whose ForceRole bot 1 sent; the settings went.
var _forced: Dictionary[int, bool] = {}
## Bot number -> its stamina as its client predicts it.
var _stamina: Dictionary[int, PredictedStamina] = {}
var _settings_sent := false
## The clients polled since they last claimed (claims_after_moves).
var _claims_due := false
## Bot number -> the client ticks its last walk covered.
var _travel_now: Dictionary[int, int] = {}
## The bots whose next claim starts a new baseline of one client tick (after a Welcome or a
## Correction), until it goes out.
var _fresh_claim: Dictionary[int, bool] = {}
## The bots whose lobby was full once (_lobby_full).
var _lobby_was_full: Dictionary[int, bool] = {}
## Bot number -> _join_clock_usec() when its last join started (add_client), and when _join_again
## first saw it fail.
var _join_started: Dictionary[int, int] = {}
var _join_failed: Dictionary[int, int] = {}


## Makes `bot`'s client on `transport` (not joined yet, or the host's own client).
func add_client(bot: ScenarioBot, transport: NetTransport) -> BotClient:
	_join_started[bot.number] = _join_clock_usec()
	_join_failed.erase(bot.number)
	var client := BotClient.new(transport, scenario.mode, schema)
	client.keep_history = true
	client.load_levels = false
	client.hold_load_ack = func() -> bool: return bot.current_step() is StepLoadAck
	client.hold_claims = claims_after_moves
	client.event_received.connect(_on_event.bind(bot))
	transport.connected.connect(_on_connected.bind(bot))
	clients[bot.number] = client
	var stamina := PredictedStamina.new(scenario.mode.player_rules)
	stamina.follow_claims()
	_stamina[bot.number] = stamina
	client.claim_sent.connect(
		func(epoch: int, tick: int, covered: int, sprint: bool, moved: bool) -> void:
			stamina.settle_claim(epoch, tick, covered, sprint, moved, bot.downed)
	)
	# A method, not the lambda's: a lambda that reads a member holds this runner, and the client it
	# holds would never be freed.
	client.claim_sent.connect(_on_claim_sent.bind(bot))
	client.corrected.connect(
		func(_position: Vector3, _velocity: Vector3) -> void: stamina.forget_unclaimed_jumps()
	)
	return client


## Steps every bot's client at now_usec. With claims_after_moves the claims wait for
## claim_clients(); those of a frame that played no play_frame go out here, first.
func step_clients() -> void:
	if _claims_due:
		claim_clients()
	for bot: ScenarioBot in bots:
		var client: BotClient = clients.get(bot.number)
		if client == null or client.is_ended():
			continue
		client.step(now_usec)
		if client.model.snapshot_tick != _snapshot_seen.get(bot.number, -1):
			_snapshot_seen[bot.number] = client.model.snapshot_tick
			bot.see(client.model.avatars)
	_claims_due = claims_after_moves


## Each client sends the MoveClaim due by now_usec, with its bot's move of this frame.
func claim_clients() -> void:
	_claims_due = false
	for bot: ScenarioBot in bots:
		var client: BotClient = clients.get(bot.number)
		if client != null and not client.is_ended():
			client.claim(now_usec)


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
	if _claims_due:
		claim_clients()


## A claim went out: the bot's fresh baseline, if any, is behind it.
func _on_claim_sent(
	_epoch: int, _tick: int, _covered: int, _sprint: bool, _moved: bool, bot: ScenarioBot
) -> void:
	_fresh_claim.erase(bot.number)


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
		return
	_disconnected(bot, at_tick)


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
	if event_name == &"SelfStatus":
		_stamina[bot.number].follow_status(
			fields["stamina"] as int,
			fields["sprint_available"] as bool,
			fields["claim_tick"] as int,
			clients[bot.number].model.epoch
		)
	if event_name == &"Welcome" or event_name == &"Correction":
		# The claim that follows may cover one client tick (ClientSession's fresh baseline after
		# a Welcome or a placement): until it goes out the bot moves one tick at most.
		_fresh_claim[bot.number] = true
	var problem := bot.receive(event_name, fields)
	if not problem.is_empty():
		_fail_step(bot, problem)
	if event_name == &"Rejected" and bot.joined and fields["seq"] != bot.sent_seq:
		_fail_step(bot, "Rejected (%s) for intent %d" % [fields["reason"], fields["seq"]])
	if ends_from_bots and event_name == MATCH_ENDED:
		ends.append(StringName(str(fields["side"])))


func _before_steps(bot: ScenarioBot) -> void:
	if bot.dead:
		# A dead bot never stands (ScenarioPlay._act): its first walk after Respawned covers one
		# client tick, not the whole time since its last walk.
		_moved_tick.erase(bot.number)
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
	if scenario.clock_s > 0 and client.force_clock(host.peer, scenario.clock_s) < 0:
		_fail_step(host, "could not send ForceClock")
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


## A bot that joins at the start: no Join step first in its script.
func _joins_at_start(number: int) -> bool:
	var steps := scenario.steps_of(number)
	return steps.is_empty() or not steps[0] is StepJoin


## Whether `bot`'s lobby is full: every other player that joins at the start has a known peer id
## and is in the lobby `bot` decoded (its Welcome's positions or a PlayerJoined); once true, true
## for good. Over ENet the joins take frames, and under load a process can start seconds after the
## host's: a bot that readied before the others joined started the round without them (a lone
## dissident wins at once), or a late joiner cancelled the countdown (#284). Waiting for the peer
## ids alone (`connected`) does not cover the second: the Hello is admitted later (#318).
func _lobby_full(bot: ScenarioBot) -> bool:
	if _lobby_was_full.has(bot.number):
		return true
	for number in range(1, scenario.bots + 1):
		if number == bot.number or not _joins_at_start(number):
			continue
		var other := peers.peer_of(number)
		if other == 0 or not bot.seen.has(other):
			return false
	_lobby_was_full[bot.number] = true
	return true


## Why `bot` still waits for its lobby, for a run that ran out of time; "" once it was full.
func _lobby_wait(bot: ScenarioBot) -> String:
	if _lobby_full(bot):
		return ""
	return (
		"bot %d waited for the lobby: peers %s, players seen %s"
		% [bot.number, peers.to_dict(), bot.seen.keys()]
	)


## A bot that joins at the start joins again when its join went unanswered: it failed (UNANSWERED)
## UNANSWERED_USEC or more after it started, as EnetTransport ends a join the host never admitted
## after JOIN_TIMEOUT_MS. Under load its process can start seconds
## before the host's listens, and it sat out the run unheard (#284). A host that refuses a join
## answers at once: before the admission (refusing new connections, an id in use) the client also
## ends `connect_failed`, but within a poll or two, and after it (a Rejected Hello) `host_lost`;
## both stay failures (_lost), as do WebRTC's `joins_closed`, `full` and `host_unreachable`. Over
## WebRTC a join that found no room (ROOM_NOT_UP: the host's process or room is not up yet) joins
## again ROOM_RETRY_USEC after it ended. Judged when the failure is first seen, on
## _join_clock_usec().
func _join_again(bot: ScenarioBot) -> void:
	var client: BotClient = clients.get(bot.number)
	if client == null or bot.joined or bot.gone or bot.joins_late():
		return
	var reason := client.end_reason
	# Over WebRTC connect_failed is a connection that closed or a bad ADMIT, never a missing answer.
	var unanswered := reason in UNANSWERED and not client.transport() is WebRtcTransport
	if not unanswered and not reason in ROOM_NOT_UP:
		return
	var failed: int = _join_failed.get_or_add(bot.number, _join_clock_usec())
	if reason in ROOM_NOT_UP:
		if _join_clock_usec() - failed < ROOM_RETRY_USEC:
			return
	elif failed - _join_started.get(bot.number, failed) < UNANSWERED_USEC:
		return
	print(
		"%s: bot %d joins again (%s: the host did not answer)" % [_log_label(), bot.number, reason]
	)
	_join_host(bot)


## The clock _join_again judges a join on, in microseconds: the runner's (now_usec), which is the
## real one over ENet. A runner on a simulated clock returns the real one: EnetTransport's
## JOIN_TIMEOUT_MS is real time.
func _join_clock_usec() -> int:
	return now_usec


## What starts this runner's log lines (_join_again's).
func _log_label() -> String:
	return "BOTS"


## With claims_after_moves, the client ticks since the bot's last move or its client's last claim,
## the later: this frame's claim covers them (one after a Welcome or a placement, or the first).
## Otherwise one in a frame whose client tick rose, never the ticks a stall skipped (#284): the
## client claimed at the start of the frame, before the bot moved, so the next claim covers one
## client tick or a few and must not carry the stall's travel.
func _travel_ticks(bot: ScenarioBot) -> int:
	var client: BotClient = clients[bot.number]
	var now_tick := client.client_tick(now_usec)
	var ticks := 0
	if claims_after_moves:
		var moved: int = _moved_tick.get(bot.number, -1)
		var from := maxi(moved, client.last_claim_tick())
		ticks = now_tick - from
		if _fresh_claim.has(bot.number) or client.last_claim_tick() < 0:
			ticks = mini(1, ticks)
	else:
		var last: int = _moved_tick.get(bot.number, now_tick - 1)
		ticks = mini(1, now_tick - last)
	_moved_tick[bot.number] = now_tick
	_travel_now[bot.number] = ticks
	return ticks


func _claim(bot: ScenarioBot, to: Vector3, velocity: Vector3, sprint: bool) -> void:
	var facing := velocity.normalized() if not velocity.is_zero_approx() else Vector3.FORWARD
	_facing_of[bot.number] = facing
	clients[bot.number].set_motion(to, velocity, facing, sprint, true, true)
	bot.position = to


func _stand(bot: ScenarioBot) -> void:
	var client: BotClient = clients.get(bot.number)
	if client == null:
		return
	# A walk after standing covers one client tick, or none in the client tick of the bot's last
	# walk: a step that ends a walk and a WalkTo that follows it in the same client tick would
	# otherwise claim two ticks of travel in one (M4-5: a PickUp answered within the tick of the
	# walk's last claim).
	if _moved_tick.get(bot.number, -1) != client.client_tick(now_usec):
		_moved_tick.erase(bot.number)
	var facing: Vector3 = _facing_of.get(bot.number, Vector3.FORWARD)
	client.set_motion(bot.position, Vector3.ZERO, facing, false, false, true)


## A walk that covers more than one client tick (after a stall) walks: the stamina it predicts
## pays for the next tick, not for every tick of the catch-up.
func _sprint_available(bot: ScenarioBot) -> bool:
	if _travel_now.get(bot.number, 1) > 1:
		return false
	var stamina := _stamina[bot.number]
	return stamina.can_sprint(stamina.is_sprinting(), bot.downed)


func _jump(bot: ScenarioBot) -> void:
	bot.jumps += 1
	clients[bot.number].count_jump()
	_stamina[bot.number].report(0.0, false, true, bot.downed)


func _leave(bot: ScenarioBot) -> void:
	clients[bot.number].leave()


func _answer_load(bot: ScenarioBot, match_id: int, skip: bool) -> void:
	if not skip:
		clients[bot.number].send_load_ack(match_id)


## Its synthetic voice frames due since the last frame (BotVoice), once the bot is a player and
## while it talks (a Talk step).
func _speak(bot: ScenarioBot) -> void:
	var client: BotClient = clients.get(bot.number)
	if bot.gone or not bot.joined or client == null or client.is_ended():
		return
	var now_frame := BotVoice.frame_at(now_usec)
	var last: int = _voice_frame.get(bot.number, now_frame - 1)
	_voice_frame[bot.number] = now_frame
	if not bot.talking:
		return
	for _frame: int in BotVoice.frames_due(bot.number, last, now_frame, scenario.voice):
		var counter: int = _voice_count.get(bot.number, 0)
		if client.send_voice(LeakCheck.voice_frame(bot.peer, counter)) != OK:
			return
		_voice_count[bot.number] = counter + 1
