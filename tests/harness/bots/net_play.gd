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
## whose join went unanswered joins again (_join_again). A join it does not join again is lost for
## good: its bot's step fails at once, naming the reason it ended and those of its earlier joins
## (_lost_join, #483), never a silent bot that sits the run out until the time limit. The rule of
## when a join is tried again is JoinRetry's; the watchers (the lurker and the refused bot) of the
## runners that run them join again by the same rule (_watcher_join_again, #509).

## The schema every bot and host uses: a debug build's, which has ForceRole's kind (E17).
var schema := WireSchema.game(true)
## Bot number -> its client.
var clients: Dictionary[int, BotClient] = {}
## Bot number -> the clients of its earlier connections that reached a Welcome, oldest first: a bot
## that left and joined again (ScenarioBot.lives), each checked as its own view.
var earlier_clients: Dictionary[int, Array] = {}
## The peer id the transport gave each of `earlier_clients`' connections (the bot's `peer` when it
## left), in the same order: the anchor a Welcome's own id is checked against.
var earlier_peers: Dictionary[int, Array] = {}
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
## The joins a bot that joins at the start makes at most; once the last ended, its join is lost
## for good (_lost_join). 0 is no bound: BotsEnet and the playcheck bots, whose processes a loaded
## machine starts seconds apart, wait for the host as long as it takes.
var max_joins := 0

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
## Bot number -> its joins (_join_retry): when its last one started on _join_clock_usec()
## (add_client), when _join_again first saw it fail, and why its earlier ones ended.
var _joins: Dictionary[int, JoinRetry] = {}


## Makes `bot`'s client on `transport` (not joined yet, or the host's own client).
func add_client(bot: ScenarioBot, transport: NetTransport) -> BotClient:
	_join_retry(bot.number).start(_join_clock_usec())
	var client := BotClient.new(transport, scenario.mode, schema, "", _key_of(bot))
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


## The return key `bot`'s Hello carries: fixed from its number (ScenarioBot.key_of), over every
## transport. The chaos run gives its hostile peer an honest bot's.
func _key_of(bot: ScenarioBot) -> String:
	return ScenarioBot.key_of(bot.number)


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
			var problem := bot.see(client.model.avatars)
			if not problem.is_empty():
				_fail_step(bot, problem)
	_claims_due = claims_after_moves


## Each client sends the MoveClaim due by now_usec, with its bot's move of this frame.
func claim_clients() -> void:
	_claims_due = false
	for bot: ScenarioBot in bots:
		var client: BotClient = clients.get(bot.number)
		if client != null and not client.is_ended():
			client.claim(now_usec)


## Every bot acts on what it decoded so far, at tick `at_tick` of the runner's clock, then speaks;
## none acts while a watcher's join is still open (_watchers_settled).
func play_frame(at_tick: int) -> void:
	if not _watchers_settled():
		return
	for bot: ScenarioBot in bots:
		if not bot.acts() or not failures.is_empty():
			continue
		var client: BotClient = clients.get(bot.number)
		if client != null and client.is_ended() and not bot.returns():
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
## Join step first reads the Rejected that refused it. A bot that joins at the start and never
## joined fails at once, whatever ended its join (_lost_join), unless _join_again joins it again.
func _lost(bot: ScenarioBot, client: BotClient, at_tick: int) -> void:
	if bot.returning():
		_lost_try(bot, client, at_tick)
		return
	if not bot.joined and not bot.joins_late():
		if _joins_again(bot):
			return
		tick_now = at_tick
		_fail_lost_join(bot)
		return
	if not bot.joined:
		if client.end_reason == ClientSession.CONNECT_FAILED:
			tick_now = at_tick
			_fail_step(bot, "the host refuses new connections (connect_failed)")
		else:
			_act(bot, at_tick)
		bot.gone = true
		return
	_disconnected(bot, at_tick)


## A returning Join's try ended before its Welcome: refused at connecting (connect_failed) or by a
## Rejected Hello (joins_closed), it tries again (ScenarioPlay._try_again); any other end fails it.
func _lost_try(bot: ScenarioBot, client: BotClient, at_tick: int) -> void:
	tick_now = at_tick
	var rejected := String(bot.rejection_of(bot.sent_seq))
	var reason := rejected if not rejected.is_empty() else String(client.end_reason)
	_try_again(bot, reason, at_tick, false)


## The tick after its Leave: the client it left on keeps its view (earlier_clients), and its next
## connection starts with nothing a connection learns.
func _begin_return(bot: ScenarioBot) -> void:
	var client: BotClient = clients.get(bot.number)
	if client != null:
		var earlier: Array = earlier_clients.get(bot.number, [])
		earlier.append(client)
		earlier_clients[bot.number] = earlier
		var transport_peers: Array = earlier_peers.get(bot.number, [])
		transport_peers.append(bot.peer)
		earlier_peers[bot.number] = transport_peers
	_forget_connection(bot.number)
	bot.begin_return(0)


## A refused try never joined: its client holds no view of the game, and it decoded no snapshot and
## no voice (its events were checked by ScenarioPlay._try_again).
func _drop_try(bot: ScenarioBot, _was_connected: bool) -> void:
	var client: BotClient = clients.get(bot.number)
	if client != null:
		var view := client.view
		if not view.snapshots.is_empty() or not view.voice.is_empty() or view.voice_batches > 0:
			failures.append(
				(
					(
						"bot %d: its refused Join decoded %d snapshots, voice of %d speaker-ticks"
						+ " and %d VoiceBatches, a peer that is not a player"
					)
					% [bot.number, view.snapshots.size(), view.voice.size(), view.voice_batches]
				)
			)
	_forget_connection(bot.number)
	bot.peer = 0


## Each earlier connection of `bot` that reached a Welcome, oldest first: {peer, view, order} (its
## view file's `earlier`, ViewFile.write).
func earlier_views(bot: ScenarioBot) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var lives: Array = earlier_clients.get(bot.number, [])
	for i in lives.size():
		var client: BotClient = lives[i]
		found.append({"peer": earlier_peer(bot, i), "view": client.view, "order": order_of(client)})
	return found


## The peer id the transport gave `bot`'s earlier connection `index` (earlier_clients), not the one
## its Welcome names: a misrouted stream carries the other peer's own id.
func earlier_peer(bot: ScenarioBot, index: int) -> int:
	var transport_peers: Array = earlier_peers.get(bot.number, [])
	return transport_peers[index]


## The OrderLog lists of `client`'s messages from the host over WebRTC (BotWebRtc), else empty.
static func order_of(client: BotClient) -> Dictionary:
	if client.transport() is BotWebRtc:
		return (client.transport() as BotWebRtc).order.to_data(NetTransport.HOST_ID)
	return {}


func _forget_connection(number: int) -> void:
	clients.erase(number)
	for per_bot: Dictionary in [
		_moved_tick,
		_voice_frame,
		_voice_count,
		_facing_of,
		_snapshot_seen,
		_fresh_claim,
		_travel_now,
		_lobby_was_full,
	]:
		per_bot.erase(number)


func _on_connected(own_id: int, bot: ScenarioBot) -> void:
	if not bot.lives.is_empty() and peers.bot_of(own_id) != 0:
		_fail_step(bot, "its return got peer id %d, used before in the session" % own_id)
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
	var args := scenario.setup_change()
	if args.is_empty():
		return
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


## Why `bot` still waits for its lobby or the watchers (_watchers_settled), for a run that ran out
## of time; "" once neither holds it.
func _lobby_wait(bot: ScenarioBot) -> String:
	if not _lobby_full(bot):
		return (
			"bot %d waited for the lobby: peers %s, players seen %s"
			% [bot.number, peers.to_dict(), bot.seen.keys()]
		)
	if _watchers_settled():
		return ""
	var open := PackedStringArray()
	for watcher: BotWatcher in _watchers():
		if not _watcher_settled(watcher):
			open.append("%s (join %d)" % [watcher.label, watcher.joins.ends.size() + 1])
	return "bot %d waited for the watchers: %s" % [bot.number, ", ".join(open)]


## A bot that joins at the start joins again when its join went unanswered or found no room, by
## JoinRetry's rule (its bound max_joins): under load its process can start seconds before the
## host's listens, and it sat out the run unheard (#284). A refusal stays a failure (_lost). Judged
## when the failure is first seen, on _join_clock_usec(). It keeps the reason each join ended, for
## the line of a join lost for good.
func _join_again(bot: ScenarioBot) -> void:
	var client: BotClient = clients.get(bot.number)
	if client == null or bot.joined or bot.gone or bot.joins_late() or not bot.lives.is_empty():
		return
	var reason := client.end_reason
	if not _join_retry(bot.number).join_again(reason, client.transport(), _join_clock_usec()):
		return
	print(
		(
			"%s: bot %d joins again (%s: %s)"
			% [_log_label(), bot.number, reason, JoinRetry.why(reason)]
		)
	)
	_join_host(bot)


## Whether _join_again joins `bot` again, now or after JoinRetry.ROOM_RETRY_USEC (JoinRetry's
## joins_again: only _join_again records a failure, so a runner that never calls it joins nobody
## again). Writes nothing.
func _joins_again(bot: ScenarioBot) -> bool:
	var client: BotClient = clients.get(bot.number)
	if client == null or not _joins.has(bot.number):
		return false
	return _join_retry(bot.number).joins_again(client.end_reason, client.transport())


## Why `bot`'s join is lost for good, or "": it joins at the start, never joined, its client ended
## and _join_again does not join it again. Names the reason it ended (a NetTransport JOIN_* reason
## or ClientSession's), and the reasons its earlier joins ended.
func _lost_join(bot: ScenarioBot) -> String:
	var client: BotClient = clients.get(bot.number)
	if (
		client == null
		or not client.is_ended()
		or bot.joined
		or bot.gone
		or bot.joins_late()
		or not bot.lives.is_empty()
	):
		return ""
	if _joins_again(bot):
		return ""
	return (
		"its join was lost for good (%s)%s" % [client.end_reason, _join_retry(bot.number).earlier()]
	)


## Fails `bot`'s step when its join is lost for good (_lost_join): it acts no more. True if it did.
func _fail_lost_join(bot: ScenarioBot) -> bool:
	var why := _lost_join(bot)
	if why.is_empty():
		return false
	_fail_step(bot, why)
	bot.gone = true
	return true


## `bot`'s JoinRetry, made on first use, bounded by max_joins as it is now.
func _join_retry(number: int) -> JoinRetry:
	var retry: JoinRetry = _joins.get(number)
	if retry == null:
		retry = JoinRetry.new()
		_joins[number] = retry
	retry.max_joins = max_joins
	return retry


## A new transport joining the host, for a watcher (and in the runners that join bots, a bot):
## null in a runner that runs no watchers.
func _joining() -> NetTransport:
	return null


## The watchers this runner runs (the lurker and the refused bot, once made): none here.
func _watchers() -> Array[BotWatcher]:
	return []


## Whether every watcher's join is settled (_watcher_settled). Until then no bot acts (play_frame):
## the match must not leave its lobby while a watcher may still join again. Its Loading refuses new
## joins (RefuseJoinsEvent; over WebRTC the room closes), so a join again that came after the bots
## readied at once was refused, and the leak test failed the run for a watcher that never connected
## (#509). Over the loopback the watchers connect in the first frame, before any bot acts.
func _watchers_settled() -> bool:
	for watcher: BotWatcher in _watchers():
		if not _watcher_settled(watcher):
			return false
	return true


## Whether `watcher` connected, or its join is lost for good: it ended for a reason JoinRetry does
## not join again, or after its last allowed join. _watcher_join_again records the failure before
## this is asked (JoinRetry.joins_again needs it).
func _watcher_settled(watcher: BotWatcher) -> bool:
	if watcher.peer != 0:
		return true
	if watcher.failed_reason.is_empty():
		return false
	return not watcher.joins.joins_again(watcher.failed_reason, watcher.transport)


## `watcher` (the lurker or the refused bot, just made on _joining()), its join started now.
func _watching(watcher: BotWatcher) -> BotWatcher:
	watcher.joins.start(_join_clock_usec())
	return watcher


## Joins `watcher` again on a new _joining() while it never connected and its join was lost the way
## a bot's is joined again (JoinRetry, within BotWatcher.MAX_JOINS): over a network under load its
## join can go unanswered or end at the signalling's 5 s cap (`service_unreachable`), and the leak
## test then failed the run for a watcher that never connected (#509). Every other end, or the last
## allowed join's, stays: the leak test names its reason and the earlier ones (LeakCheck).
func _watcher_join_again(watcher: BotWatcher) -> void:
	if watcher == null or watcher.peer != 0:
		return
	if not watcher.joins.join_again(watcher.failed_reason, watcher.transport, _join_clock_usec()):
		return
	var transport := _joining()
	if transport == null:
		return
	print(
		(
			"%s: the %s joins again (%s: %s)"
			% [
				_log_label(),
				watcher.label,
				watcher.failed_reason,
				JoinRetry.why(watcher.failed_reason),
			]
		)
	)
	watcher.rejoin(transport, _join_clock_usec())


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
