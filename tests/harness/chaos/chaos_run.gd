class_name ChaosRun
extends BotsRunner
## The chaos bots (ARCHITECTURE invariant 1, the host validates every intent; §4.6 "Chaos"): the
## bots runner's match (ChaosScenario) with two chaos peers that are never peer 1, a "hostile but
## valid" player (ChaosHostile, on bot 4's connection) and a "malformed" peer that never becomes a
## player (ChaosMalformed). Everything BotsRunner asserts still holds for every bot, the leak test
## whole, plus one rule per input class, each from ARCHITECTURE:
## 1. a malformed frame, a wrong direction or lane, a payload over its cap, a debug kind from a peer
##    other than 1: dropped by NetFrame or the codec, counted under its reason, no reply; no role
##    changes (the forced roles are the ones the match has);
## 2. a message over a budget: counted OVER_BUDGET, no reply, no disconnect;
## 3. the malformed peer: disconnected at MALFORMED_LIMIT within the window, one log line naming it;
## 4. an intent the phase or the rules refuse: exactly Rejected(seq, reason) to its sender, the
##    reason ChaosOracle's, nothing else emitted (no state change), no reject counted;
## 5. a hostile MoveClaim: a Correction (new epoch, the old position) or a silent drop by §7.1 and
##    E15, the position unchanged, never Rejected;
## 6. repeated, replayed and out-of-order seqs: each copy answered by the rule, echoing its seq
##    (4 and 5 check every copy);
## 7. no honest bot decodes a frame of the malformed peer, nor of the hostile while it is downed or
##    dead or in a phase where nobody hears anyone (radius 0: Loading, Pregame, End);
## 8. (compare_rejected) the hostile's Rejected stream is the same when only hidden roles differ.
## In one process over the loopback the host's counts are replayed exactly (ChaosBudget) and the
## honest bots' decoded views equal a baseline run's with the chaos peers joined but idle
## (compare_honest). Over ENet only the invariants hold: no crash, no engine error line, the leak
## check, the counters, and 4 to 7, which the host's state decides at each call. Over WebRTC
## (`webrtc`, M6-6) the same, on BotWebRtc transports with the fault shim on and LanSignalling
## on the port, paced to the real clock (WebRTC's connections and the shim's delays are real
## time), plus the leak test's order check (OrderLog) of every peer but the host's own bot: both
## ways for the honest bots and the watchers, from the host only for the chaos peers (their raw
## sends bypass the recording). Over WebRTC the run first sets the library up (a WebRtcWarmUp,
## kept until close()): under load the setup took seconds, and in a first connection it counted
## against the join's JOIN_TIMEOUT_MS (#510).

enum Mode { BASELINE, CHAOS }

const HOSTILE := ChaosScenario.HOSTILE
const HONEST: Array[int] = [1, 2, 3]
const ENET_ADDRESS := "127.0.0.1"
## The base mode's silent phases by hand from §6; class 7 checks the mode against them.
const SILENT_PHASES: Array[StringName] = [&"loading", &"pregame", &"end"]
## Frames run after the match over ENet, so what is in flight arrives before the views are compared.
const ENET_DRAIN_FRAMES := 120
## The fault shim's seeds over WebRTC: this plus the chaos seed times SHIM_SEED_STRIDE, plus a count
## of the run's transports.
const SHIM_SEED := 188_000
const SHIM_SEED_STRIDE := 16
## The joins each bot makes at most over the network (NetPlay.max_joins, #483): the host is up in
## this process before the bots join, and three attempts fail before the runner's kill (120 s per
## seed over a network, bots.CHAOS_NETWORK_SECONDS_PER_SEED; over WebRTC a retried join, no room,
## ends within the 5 s signalling cap plus the 0.5 s wait; over ENet an unanswered one after
## EnetTransport.JOIN_TIMEOUT_MS, 5 s; a WebRTC host_unreachable, 15 s, is never retried, so it
## uses one attempt).
const MAX_JOINS := 3
const WireSamples := preload("res://tests/unit/net/messages/wire_samples.gd")
const WebRtcWarmUp := preload("res://tests/integration/net/webrtc_warm_up.gd")

var chaos_mode := Mode.CHAOS
var chaos_seed := 1
## Over a network on 127.0.0.1 (ENet, or WebRTC with `webrtc`), not the loopback.
var over_network := false
var webrtc := false
var swapped := false
var hostile: ChaosHostile
var malformed: ChaosMalformed
var ledger: RejectLedger
var chaos_log := ChaosLog.new()
## Chaos peer -> the commands of it whose answers the oracle checked.
var checked: Dictionary[int, int] = {}
## The hostile's Rejected answers as it decoded them, "seq reason", in order.
var hostile_rejected := PackedStringArray()

var _hostile_client: BotClient
var _hostile_budget := ChaosBudget.new()
var _malformed_budget := ChaosBudget.new()
var _take_hostile := Callable()
var _take_malformed := Callable()
var _claimed_tick := -1
var _corrections_seen := 0
## Peer -> its epoch and position after the last Match call (Welcome and Correction events).
var _epoch_of: Dictionary[int, int] = {}
var _position_of: Dictionary[int, Vector3] = {}
var _welcomed: Dictionary[int, bool] = {}
## Over ENet, chaos peer -> NetRejects reason -> the chaos packets it sent that must be counted
## under that reason (the bound of its counts, there being no exact replay).
var _chaos_sent: Dictionary[int, Dictionary] = {}
## Host tick -> the hostile's life and the phase after that tick.
var _life_at: Dictionary[int, int] = {}
var _phase_at: Dictionary[int, StringName] = {}
## Peer -> its role after the last call in the round or End: End's return to the lobby (3 s after
## the end, #212; a slow network run outlasts it) resets every role, so the role check reads these.
var _role_of: Dictionary[int, StringName] = {}
## Over WebRTC: the host's signalling service and transport, the transports made, and when the run
## started on the real clock (the pace).
var _signalling: LanSignalling
var _host_rtc: BotWebRtc
var _transports_made := 0
var _real_start_usec := -1
var _warm_up: WebRtcWarmUp


func _init(
	roles_swapped := false,
	run_mode := Mode.CHAOS,
	seed_value := 1,
	net_port := 0,
	until_dead := false,
	over_webrtc := false
) -> void:
	super(ChaosScenario.build(roles_swapped, until_dead))
	swapped = roles_swapped
	chaos_mode = run_mode
	chaos_seed = seed_value
	if net_port > 0:
		over_network = true
		webrtc = over_webrtc
		port = net_port
		one_process = false
		max_joins = MAX_JOINS


## Plays one run to its end and closes it; see `failures`.
static func play_one(
	roles_swapped: bool,
	run_mode: Mode,
	seed_value: int,
	net_port := 0,
	until_dead := false,
	over_webrtc := false
) -> ChaosRun:
	var runner := ChaosRun.new(
		roles_swapped, run_mode, seed_value, net_port, until_dead, over_webrtc
	)
	runner.run()
	runner.close()
	return runner


## Where the honest bots' decoded views of `chaos` differ from `baseline`'s, apart from the
## hostile's voice (the chaos voice is relayed like any): events and snapshots exactly, voice frames
## and their seqs per speaker, and the ends.
static func compare_honest(baseline: ChaosRun, chaos: ChaosRun) -> PackedStringArray:
	var found := PackedStringArray()
	if baseline.ends != chaos.ends:
		found.append("the ends differ: %s, with chaos %s" % [baseline.ends, chaos.ends])
	var hostile_id := chaos.peers.peer_of(HOSTILE)
	for number: int in HONEST:
		var a: DecodedView = baseline.clients[number].view
		var b: DecodedView = chaos.clients[number].view
		var label := "bot %d" % number
		if a.events.size() != b.events.size():
			found.append(
				"%s decoded %d events, with chaos %d" % [label, a.events.size(), b.events.size()]
			)
		for i in mini(a.events.size(), b.events.size()):
			var x := a.events[i]
			var y := b.events[i]
			if x.name != y.name or not WireSamples.same(x.fields, y.fields):
				found.append(
					(
						"%s event %d: %s %s, with chaos %s %s"
						% [label, i, x.name, x.fields, y.name, y.fields]
					)
				)
				break
		if not WireSamples.same(a.snapshots, b.snapshots):
			found.append("%s decoded other snapshots with chaos" % label)
		if not _same_voice(a, b, hostile_id):
			found.append("%s decoded other voice (the hostile's aside) with chaos" % label)
	return found


## Where the hostile's Rejected streams of `a` and `b` differ (only hidden roles differ between
## them, so the reasons must not: §4.1).
static func compare_rejected(a: ChaosRun, b: ChaosRun) -> PackedStringArray:
	var found := PackedStringArray()
	if a.hostile_rejected.is_empty():
		found.append("the hostile decoded no Rejected")
	if a.hostile_rejected != b.hostile_rejected:
		var first := 0
		while (
			first < mini(a.hostile_rejected.size(), b.hostile_rejected.size())
			and a.hostile_rejected[first] == b.hostile_rejected[first]
		):
			first += 1
		(
			found
			. append(
				(
					"the hostile's Rejected streams differ from answer %d (%d and %d answers): %s, %s"
					% [
						first,
						a.hostile_rejected.size(),
						b.hostile_rejected.size(),
						a.hostile_rejected.slice(first, first + 3),
						b.hostile_rejected.slice(first, first + 3),
					]
				)
			)
		)
	return found


func run() -> void:
	chaos_log.start()
	super()
	chaos_log.stop()
	for line: String in chaos_log.errors():
		failures.append("an engine error line: %s" % line)


func close() -> void:
	if malformed != null:
		malformed.close()
	super()
	if _signalling != null:
		_signalling.stop()
	if _warm_up != null:
		_warm_up.close()


## The hostile chaos peer's id; 0 before it connected.
func hostile_peer() -> int:
	return peers.peer_of(HOSTILE) if peers.has_bot(HOSTILE) else 0


func _make_host_transport() -> NetTransport:
	if webrtc:
		_warm_up = WebRtcWarmUp.new()
		if not _warm_up.wait():
			failures.append("host: the WebRTC warm-up failed: %s" % _warm_up.error_text)
		_signalling = BotWebRtc.signalling()
		if _signalling.listen(port, ENET_ADDRESS) != OK:
			failures.append("cannot serve signalling on %s:%d" % [ENET_ADDRESS, port])
		_host_rtc = BotWebRtc.new(schema.kind_table(), port, _shim_seed())
		ledger = _host_rtc.ledger
		return _host_rtc
	if over_network:
		var enet := CountingEnet.new(schema.kind_table())
		enet.bind_address = ENET_ADDRESS
		ledger = enet.ledger
		return enet
	var loopback := CountingLoopback.new(schema.kind_table(), hub)
	ledger = loopback.ledger
	return loopback


func _joining() -> NetTransport:
	if not over_network:
		return super()
	if webrtc:
		var rtc := BotWebRtc.new(schema.kind_table(), port, _shim_seed())
		rtc.join(BotWebRtc.CODE, 0)
		return rtc
	var transport := EnetTransport.new(schema.kind_table())
	transport.join(ENET_ADDRESS, port)
	return transport


## A chaos transport joining the host: `take` gets its outbox, `send_raw` its raw sends.
func _chaos_joining() -> Dictionary:
	if webrtc:
		var rtc := BotWebRtc.new(schema.kind_table(), port, _shim_seed())
		rtc.keep_outbox = true
		rtc.join(BotWebRtc.CODE, 0)
		return {"transport": rtc, "take": rtc.take_outbox, "send_raw": rtc.send_raw}
	if over_network:
		var enet := ChaosEnet.new(schema.kind_table())
		enet.join(ENET_ADDRESS, port)
		return {"transport": enet, "take": enet.take_outbox, "send_raw": enet.send_raw}
	var loopback := ChaosLoopback.new(schema.kind_table(), hub)
	loopback.join("loopback", port)
	return {"transport": loopback, "take": loopback.take_outbox, "send_raw": loopback.send_raw}


func _join_host(bot: ScenarioBot) -> String:
	if bot.number != HOSTILE:
		return super(bot)
	var joined := _chaos_joining()
	_hostile_client = add_client(bot, joined["transport"] as NetTransport)
	_take_hostile = joined["take"]
	if chaos_mode == Mode.CHAOS:
		var budget: ChaosBudget = null if over_network else _hostile_budget
		hostile = ChaosHostile.new(
			bot, _hostile_client, schema, joined["send_raw"] as Callable, budget, chaos_seed
		)
	return ""


func _join_everyone() -> void:
	super()
	var joined := _chaos_joining()
	_take_malformed = joined["take"]
	malformed = ChaosMalformed.new(
		joined["transport"] as NetTransport, joined["send_raw"] as Callable, schema, chaos_seed + 1
	)
	malformed.active = chaos_mode == Mode.CHAOS


## The fault shim's seed for the run's next WebRTC transport.
func _shim_seed() -> int:
	_transports_made += 1
	return SHIM_SEED + chaos_seed * SHIM_SEED_STRIDE + _transports_made


## Over WebRTC the host takes joins once the signalling opened its room.
func _host_ready() -> bool:
	if _host_rtc == null or not failures.is_empty():
		return failures.is_empty()
	if not BotWebRtc.wait_for_room(_signalling, _host_rtc):
		failures.append("host: the signalling opened no room in %d ms" % BotWebRtc.ROOM_WAIT_MS)
		return false
	return true


## Over WebRTC each frame waits for the real clock to reach the simulated one: the connections and
## the fault shim's delays run in real time, and a frame run at once would read a 50 ms delay as
## dozens of host ticks.
func _frame_usec(frame: int) -> int:
	if webrtc:
		_pace()
	return super(frame)


func _pace() -> void:
	var real := Time.get_ticks_usec()
	if _real_start_usec < 0:
		_real_start_usec = real - (now_usec - START_USEC)
	var ahead := (now_usec - START_USEC) - (real - _real_start_usec)
	if ahead > 0:
		OS.delay_usec(ahead)


## The host just polled what the chaos peers sent in the frame before: replay its bookkeeping.
func _after_host_step() -> void:
	if _signalling != null:
		_signalling.poll()
	var from_hostile: Array[ChaosFrames.Packet] = _take_hostile.call()
	var from_malformed: Array[ChaosFrames.Packet] = _take_malformed.call()
	if over_network:
		_note_chaos_sent(hostile_peer(), from_hostile)
		_note_chaos_sent(malformed.peer if malformed != null else 0, from_malformed)
		return
	_hostile_budget.poll(now_usec, FRAME_USEC, from_hostile)
	_malformed_budget.poll(now_usec, FRAME_USEC, from_malformed)


func _note_chaos_sent(peer: int, packets: Array[ChaosFrames.Packet]) -> void:
	if peer == 0:
		return
	var by_reason: Dictionary = _chaos_sent.get_or_add(peer, {})
	for packet: ChaosFrames.Packet in packets:
		if packet.label != "honest" and packet.expect != NetRejects.Reason.NONE:
			by_reason[packet.expect] = by_reason.get(packet.expect, 0) + 1


func play_frame(at_tick: int) -> void:
	if over_network:
		# A join lost for good fails its bot at once, before any bot acts (#483): over WebRTC the
		# run is paced to the real clock, and its time limit would report it 90 s later.
		for bot: ScenarioBot in bots:
			_join_again(bot)
			_fail_lost_join(bot)
		if not failures.is_empty():
			return
		if not _may_play():
			malformed.poll()
			return
	super(at_tick)
	malformed.poll()
	if chaos_mode == Mode.CHAOS and failures.is_empty():
		var claimed := _hostile_client.last_claim_tick() != _claimed_tick
		hostile.act(now_usec, claimed)
		malformed.act(peers.peer_of(2))
	_claimed_tick = _hostile_client.last_claim_tick()


## Over ENet the joins take frames: the bots play once bot 1's lobby is full (NetPlay._lobby_full,
## as BotsEnet's bot 1 waits, #318). play_frame fails a join lost for good (NetPlay._lost_join)
## before it asks, so the second test only covers a caller that asks first (a unit test, say); a
## join that waits for its retry (no room yet) does not start them. Over the loopback they play
## at once.
func _may_play() -> bool:
	if not over_network or _lobby_full(bots[0]):
		return true
	for bot: ScenarioBot in bots:
		if not _lost_join(bot).is_empty():
			return true
	return false


## A join over ENet is judged on the real clock (EnetTransport's JOIN_TIMEOUT_MS is real time), not
## this runner's simulated one, which moves one frame per frame however long the frame took.
func _join_clock_usec() -> int:
	return Time.get_ticks_usec() if over_network else now_usec


func _log_label() -> String:
	return "CHAOS seed %d" % chaos_seed


func _fail_time_limit() -> void:
	super()
	if over_network and not bots.is_empty():
		var waited := _lobby_wait(bots[0])
		if not waited.is_empty():
			failures.append(waited)


func _play() -> void:
	super()
	if not over_network or not failures.is_empty():
		return
	# Over ENet what is still in flight arrives before the views are compared.
	for _i in ENET_DRAIN_FRAMES:
		if webrtc:
			_pace()
		now_usec += FRAME_USEC
		session.step(now_usec)
		if not session.is_running():
			return
		_after_host_step()
		step_clients()
		lurker.poll()
		refused.poll()
		malformed.poll()


## The hostile's answers to its chaos never reach its bot's script: the script is the baseline's.
func _on_event(event_name: StringName, fields: Dictionary, bot: ScenarioBot) -> void:
	if bot.number == HOSTILE and _is_chaos_answer(event_name, fields, bot):
		return
	super(event_name, fields, bot)


func _is_chaos_answer(event_name: StringName, fields: Dictionary, bot: ScenarioBot) -> bool:
	if event_name == &"Rejected":
		var seq := fields["seq"] as int
		if seq >= ChaosFrames.CHAOS_SEQ or (seq == 0 and bot.joined):
			hostile_rejected.append("%d %s" % [seq, fields["reason"]])
			return true
	elif event_name == &"Correction" and _hostile_client.corrections > _corrections_seen:
		# Not a placement's (ClientSession counts those apart): a chaos claim's.
		_corrections_seen = _hostile_client.corrections
		return true
	return false


func _on_call(at_tick: int, command: MatchCommand, slice: Array[EmittedEvent]) -> void:
	super(at_tick, command, slice)
	if command != null and _is_chaos_command(command):
		checked[command.peer] = checked.get(command.peer, 0) + 1
		if command.kind == Intents.MOVE_CLAIM:
			_check_claim(command, slice)
		else:
			_check_intent(command, slice)
	for emitted: EmittedEvent in slice:
		var welcome := emitted.event as WelcomeEvent
		if welcome != null:
			_epoch_of[welcome.peer] = welcome.epoch
			_welcomed[welcome.peer] = true
		var correction := emitted.event as CorrectionEvent
		if correction != null:
			_epoch_of[correction.peer] = correction.epoch
	for peer: int in [hostile_peer(), malformed.peer if malformed != null else 0]:
		var player := game.state.player(peer) if peer != 0 else null
		if player != null:
			_position_of[peer] = player.position
	var hostile_player := game.state.player(hostile_peer()) if hostile_peer() != 0 else null
	if command == null and hostile_player != null:
		_life_at[at_tick] = hostile_player.life
		_phase_at[at_tick] = game.phase_id()
	# The roles are dealt on the row into the pregame (#213).
	if game.phase_id() in [&"pregame", &"round", &"end"]:
		for peer: int in game.state.peers():
			_role_of[peer] = game.state.player(peer).role


## A command one of the chaos peers sent as chaos (its bot's own commands are not).
func _is_chaos_command(command: MatchCommand) -> bool:
	var peer := command.peer
	if peer == 0 or (peer != hostile_peer() and (malformed == null or peer != malformed.peer)):
		return false
	if command.kind == Intents.MOVE_CLAIM:
		return ChaosFrames.claim_shape(command.args) >= 0
	if command.kind == Intents.HELLO:
		return _welcomed.has(peer)
	return Intents.ALL.has(command.kind) and command.seq >= ChaosFrames.CHAOS_SEQ


## Class 4 and 6: exactly the oracle's Rejected, echoing the seq, to the sender alone, or nothing.
func _check_intent(command: MatchCommand, slice: Array[EmittedEvent]) -> void:
	var player := game.state.player(command.peer)
	var phase := game.phase_id()
	var want := ChaosOracle.answer(
		command.kind, command.args, command.peer, phase, player, game.state.match_id(), game.state
	)
	var good := slice.is_empty() if want == ChaosOracle.SILENT else slice.size() == 1
	if good and want != ChaosOracle.SILENT:
		var rejected := slice[0].event as RejectedEvent
		good = (
			rejected != null
			and rejected.peer == command.peer
			and rejected.seq == command.seq
			and rejected.reason == want
			and slice[0].recipients == PackedInt32Array([command.peer])
		)
	if not good:
		(
			failures
			. append(
				(
					"chaos: %s seq %d of peer %d in %s (%s): expected %s, got %s"
					% [
						command.kind,
						command.seq,
						command.peer,
						phase,
						_life_name(player),
						"nothing" if want == ChaosOracle.SILENT else "Rejected %s" % want,
						_describe(slice),
					]
				)
			)
		)


## Class 5: a Correction (a new epoch, the position it had) when the phase takes the claim from its
## life state and the epoch is its own, else nothing (§7.1, E15); the position never changes.
func _check_claim(command: MatchCommand, slice: Array[EmittedEvent]) -> void:
	var peer := command.peer
	var player := game.state.player(peer)
	var shape := ChaosFrames.claim_shape(command.args)
	var before_epoch: int = _epoch_of.get(peer, 0)
	var before: Vector3 = _position_of.get(peer, Vector3.INF)
	var taken: bool = (
		player != null
		and ChaosOracle.accepts(Intents.MOVE_CLAIM, peer, game.phase_id(), player)
		and command.args.get("epoch") == before_epoch
	)
	var most := 1 if taken else 0
	var least := 1 if taken and shape != ChaosFrames.Claim.STALE_TICK else 0
	var problems := PackedStringArray()
	if slice.size() < least or slice.size() > most:
		problems.append("%d to %d Corrections expected" % [least, most])
	for emitted: EmittedEvent in slice:
		var correction := emitted.event as CorrectionEvent
		if correction == null:
			problems.append("answered with %s" % emitted.event.event_name())
		elif (
			correction.peer != peer
			or correction.epoch != before_epoch + 1
			or correction.position != before
			or emitted.recipients != PackedInt32Array([peer])
		):
			problems.append("a Correction %s" % correction.to_dict())
	if player != null and before != Vector3.INF and player.position != before:
		problems.append("it moved from %s to %s" % [before, player.position])
	if not problems.is_empty():
		(
			failures
			. append(
				(
					"chaos: claim %s of peer %d (epoch %s, %s, %s in %s): %s; got %s"
					% [
						ChaosFrames.Claim.find_key(shape),
						peer,
						command.args.get("epoch"),
						(
							"its epoch"
							if command.args.get("epoch") == before_epoch
							else "not its epoch"
						),
						_life_name(player),
						game.phase_id(),
						"; ".join(problems),
						_describe(slice),
					]
				)
			)
		)


func _check_after() -> void:
	super()
	var label := "malformed peer"
	failures.append_array(leaks.check_bot(label, malformed.peer, malformed.view, false))
	failures.append_array(
		LeakCheck.check_counters(
			label, malformed.peer, malformed.transport, malformed.undecodable, one_process
		)
	)
	if _host_rtc != null:
		_check_order()
	_check_malformed_view()
	_check_voice_rule()
	_check_roles()
	# The hostile's refused ChangeSettings carry a lobby name (#214); the host's bot never sends
	# one, so the lobby keeps its default.
	if not game.state.lobby_name.is_empty():
		failures.append("the lobby is named %s, which only the host may do" % game.state.lobby_name)
	_check_profiles()
	if chaos_mode == Mode.CHAOS:
		_check_chaos_counts()


## The hostile's SetProfiles (#551) carry a new name and colour only where no phase takes them, so
## every player ends with the name and the distinct colour it joined with: none is "Hacked" and no
## two share a colour.
func _check_profiles() -> void:
	var owners: Dictionary[int, int] = {}
	for peer: int in game.state.present_peers():
		var player := game.state.player(peer)
		if player.name == ChaosHostile.HACKED_NAME:
			failures.append(
				"peer %d is named %s, a refused SetProfile's name" % [peer, player.name]
			)
		if owners.has(player.colour):
			failures.append(
				"peers %d and %d share colour %d" % [owners[player.colour], peer, player.colour]
			)
		owners[player.colour] = peer


## Over WebRTC, the order check (OrderLog): both ways for the honest remote bots and the
## watchers; for the chaos peers only what the host sent them (their raw sends bypass `send`).
func _check_order() -> void:
	for bot: ScenarioBot in bots.slice(1):
		var client: BotClient = clients.get(bot.number)
		if client == null or bot.peer == 0 or not client.transport() is BotWebRtc:
			continue
		var own := (client.transport() as BotWebRtc).order.of(NetTransport.HOST_ID)
		var label := "bot %d" % bot.number
		if bot.number == HOSTILE:
			failures.append_array(_order_from_host(label, bot.peer, own))
		else:
			failures.append_array(_host_rtc.order.check_client(label, bot.peer, own, true))
	for watcher: BotWatcher in [lurker, refused]:
		if watcher.peer != 0:
			var lists := (watcher.transport as BotWebRtc).order.of(NetTransport.HOST_ID)
			failures.append_array(
				_host_rtc.order.check_client(watcher.label, watcher.peer, lists, true)
			)
	if malformed.peer != 0:
		var lists := (malformed.transport as BotWebRtc).order.of(NetTransport.HOST_ID)
		failures.append_array(_order_from_host("malformed peer", malformed.peer, lists))


func _order_from_host(label: String, peer: int, own: OrderLog.Lists) -> PackedStringArray:
	var mine := _host_rtc.order.of(peer)
	return OrderLog.problems("host to %s" % label, mine.sent, mine.reliable, own.delivered, true)


## A peer that is not a player and sent intents, voice and a debug kind: whatever view_of says,
## it decodes no snapshot and no voice, and no event but a not_accepted Rejected of an intent it
## sent (§3.1, §3.2, §4.4's Rejected audience: the sender alone).
func _check_malformed_view() -> void:
	var view := malformed.view
	if not view.snapshots.is_empty() or not view.repeated_snapshots.is_empty():
		failures.append("chaos: the malformed peer, no player, decoded snapshots")
	if not view.voice.is_empty():
		failures.append("chaos: the malformed peer, no player, decoded voice")
	for message: WireMessage in view.events:
		var answer := message.name == &"Rejected"
		if answer:
			var seq: int = message.fields.get("seq", -1)
			var reason: StringName = message.fields.get("reason", &"")
			answer = malformed.intent_seqs.has(seq) and reason == RejectReasons.NOT_ACCEPTED
		if not answer:
			failures.append(
				"chaos: the malformed peer decoded %s %s" % [message.name, message.fields]
			)


## Class 7: no honest bot decoded the malformed peer's voice, nor the hostile's while it was not
## living or in a phase where nobody hears anyone: the mode's phases whose voice rule hears within
## 0 m, so a new silent phase is checked too (#213). The base mode's silent phases are also written
## by hand from §6's table (SILENT_PHASES): the mode's declarations must not be the only judge, so
## a phase that loses its SilentVoice fails here whatever the routing says.
func _check_voice_rule() -> void:
	var quiet: Array[StringName] = []
	for spec: PhaseSpec in game.mode.phases:
		if VoiceRule.radius_of(spec.voice_rule) == 0.0:
			quiet.append(spec.id)
	for spec: PhaseSpec in game.mode.phases:
		if SILENT_PHASES.has(spec.id) and not quiet.has(spec.id):
			failures.append(
				"chaos: phase %s must be silent (§6) but its voice rule hears" % spec.id
			)
			quiet.append(spec.id)
	for number: int in HONEST:
		var client: BotClient = clients.get(number)
		if client == null:
			continue
		for key: Vector2i in client.view.voice:
			if malformed.peer != 0 and key.x == malformed.peer:
				failures.append("bot %d decoded voice of the malformed peer, no player" % number)
			elif key.x == hostile_peer():
				var life: int = _life_at.get(key.y, -1)
				if life != PlayerState.Life.ALIVE or quiet.has(_phase_at.get(key.y, &"")):
					failures.append(
						(
							"bot %d decoded the hostile's voice under tick %d (%s, %s)"
							% [number, key.y, _phase_at.get(key.y, &""), life]
						)
					)


## Class 1: the debug kinds from the chaos peers changed no role: each bot has its forced one, up
## to the match's reset (`_role_of`).
func _check_roles() -> void:
	for number: int in scenario.forced_roles:
		if not peers.has_bot(number):
			continue
		var peer := peers.peer_of(number)
		if game.state.player(peer) == null and not _role_of.has(peer):
			continue
		var role: StringName = _role_of.get(peer, &"")
		var want: StringName = scenario.forced_roles[number]
		if role != want:
			failures.append("bot %d has role %s, forced %s" % [number, role, want])


## Classes 1 to 3 on the host's counts.
func _check_chaos_counts() -> void:
	var hostile_id := hostile_peer()
	if not over_network:
		_check_replayed("hostile", hostile_id, _hostile_budget)
		_check_replayed("malformed peer", malformed.peer, _malformed_budget)
		if not _malformed_budget.disconnected:
			failures.append("chaos: the malformed peer never reached the malformed limit")
		if _hostile_budget.disconnected:
			failures.append("chaos: the hostile reached the malformed limit")
		if _hostile_budget.over_budget_seqs.is_empty():
			failures.append("chaos: no hostile intent went over the intents bucket")
		if ledger.of(malformed.peer, NetRejects.Reason.OVER_BUDGET) == 0:
			failures.append("chaos: no frame of the malformed peer went over the voice bucket")
	else:
		_check_bounded("hostile", hostile_id)
		_check_bounded("malformed peer", malformed.peer)
	if session.malformed_disconnects != 1:
		(
			failures
			. append(
				(
					"chaos: the host disconnected %d peers for malformed messages, not the malformed peer alone"
					% session.malformed_disconnects
				)
			)
		)
	var lines := chaos_log.disconnect_lines(malformed.peer)
	if lines.size() != 1:
		failures.append(
			(
				"chaos: %d log lines disconnect the malformed peer %d, not one: %s"
				% [lines.size(), malformed.peer, lines]
			)
		)
	if not chaos_log.disconnect_lines(hostile_id).is_empty():
		failures.append(
			"chaos: the hostile was disconnected: %s" % chaos_log.disconnect_lines(hostile_id)
		)
	if not malformed.lost:
		failures.append("chaos: the malformed peer is still connected")
	if _hostile_client.is_ended():
		failures.append("chaos: the hostile's session ended (%s)" % _hostile_client.end_reason)
	if hostile_rejected.is_empty():
		failures.append("chaos: the hostile decoded no Rejected")


## Over ENet: under each reason a malformed packet names, the host counted at most the chaos
## packets the peer sent for it, so a reject of the hostile bot's own honest traffic (a codec
## regression in MoveClaim, say) still fails the run. OVER_BUDGET (bursts and bunching) and
## UNKNOWN_PEER (in flight after a disconnect) are left out: a network decides them.
func check_bounded(label: String, peer: int) -> PackedStringArray:
	var found := PackedStringArray()
	var sent: Dictionary = _chaos_sent.get(peer, {})
	for reason: int in NetRejects.Reason.values():
		if reason in [NetRejects.Reason.OVER_BUDGET, NetRejects.Reason.UNKNOWN_PEER]:
			continue
		var counted := ledger.of(peer, reason as NetRejects.Reason)
		if counted > (sent.get(reason, 0) as int):
			found.append(
				(
					"chaos: the host counted %d %s from the %s, which sent %d such chaos packets"
					% [counted, NetRejects.Reason.find_key(reason), label, sent.get(reason, 0)]
				)
			)
	return found


func _check_bounded(label: String, peer: int) -> void:
	failures.append_array(check_bounded(label, peer))


## The host counted exactly what ChaosBudget replays for `peer`, and the oracle checked every chaos
## command that reached the session.
func _check_replayed(label: String, peer: int, budget: ChaosBudget) -> void:
	var got := ledger.named(peer)
	var want: Dictionary[String, int] = {}
	for reason: int in budget.expected:
		want[NetRejects.Reason.find_key(reason)] = budget.expected[reason]
	if not WireSamples.same(got, want):
		failures.append(
			"chaos: the host counted %s for the %s, ARCHITECTURE says %s" % [got, label, want]
		)
	var reached := 0
	for packet: ChaosFrames.Packet in budget.reached:
		if packet.label != "honest" and packet.intent != &"VoiceUp":
			reached += 1
	if reached != checked.get(peer, 0):
		failures.append(
			(
				"chaos: %d chaos commands of the %s reached the session, the oracle checked %d"
				% [reached, label, checked.get(peer, 0)]
			)
		)


## The scoped exemption of the leak test's host counts (named in the PR for the engineer): the
## host's transport rejected nothing and counted nothing over budget from any peer but the two chaos
## peers; in the baseline, from them neither.
func host_problems() -> PackedStringArray:
	var found := PackedStringArray()
	var chaos: Array[int] = [hostile_peer(), malformed.peer if malformed != null else 0]
	var others := ledger.total_except(chaos)
	if others != 0:
		found.append("the host's transport rejected %d packets of honest peers" % others)
	var chaos_over := 0
	for peer: int in chaos:
		chaos_over += ledger.of(peer, NetRejects.Reason.OVER_BUDGET)
	if session.over_budget != chaos_over:
		found.append(
			(
				"the host counted %d messages over budget, %d of them the chaos peers'"
				% [session.over_budget, chaos_over]
			)
		)
	if (
		chaos_mode == Mode.BASELINE
		and ledger.total_from(chaos[0]) + ledger.total_from(chaos[1]) != 0
	):
		found.append("the host rejected packets of the idle chaos peers")
	return found


static func _same_voice(a: DecodedView, b: DecodedView, skip: int) -> bool:
	var keys_a := a.voice.keys().filter(func(key: Vector2i) -> bool: return key.x != skip)
	var keys_b := b.voice.keys().filter(func(key: Vector2i) -> bool: return key.x != skip)
	if keys_a.size() != keys_b.size():
		return false
	for key: Vector2i in keys_a:
		if not b.voice.has(key) or not WireSamples.same(a.voice[key], b.voice[key]):
			return false
		if a.voice_seqs.get(key) != b.voice_seqs.get(key):
			return false
	return true


static func _life_name(player: PlayerState) -> String:
	return "newcomer" if player == null else str(PlayerState.Life.find_key(player.life))


static func _describe(slice: Array[EmittedEvent]) -> String:
	if slice.is_empty():
		return "nothing"
	var parts := PackedStringArray()
	for emitted: EmittedEvent in slice:
		parts.append(
			(
				"%s %s to %s"
				% [emitted.event.event_name(), emitted.event.to_dict(), emitted.recipients]
			)
		)
	return ", ".join(parts)
