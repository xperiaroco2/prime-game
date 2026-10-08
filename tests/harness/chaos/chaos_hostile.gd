class_name ChaosHostile
extends RefCounted
## The "hostile but valid" chaos peer (ARCHITECTURE invariant 1: the host validates every intent):
## a player that plays the whole round as ChaosScenario's bot 4 and, on the same connection, sends
## what a modified client can, from a seeded RandomNumberGenerator, once its own SetReady is in:
## - intents the phase or the rules refuse whatever the timing (ChaosOracle), with fresh, repeated,
##   replayed and out-of-order seqs (seq is only echoed, §4.3), and a Hello with seq 0;
## - hostile MoveClaims (ChaosFrames.Claim), at most one LATEST message per frame with its bot's own
##   claim, so the LATEST merge supersedes none;
## - malformed frames, fewer than ChaosFrames' limit within the host's window, so the host never
##   disconnects it (§4.5: 50 within 10 s), and debug kinds;
## - its synthetic voice in every phase and life state (frames the leak test can read), and one
##   burst past the voice bucket in the round and one past the reliable-intent bucket in the
##   countdown (§4.5: dropped and counted, no reply, no disconnect).
## - PickUps of items that rest far from it (out_of_reach, §9.4), some right after a claim that
##   teleports it next to the item, which the host corrects: reach is measured from the host's
##   last accepted position, never the claimed one (§7.1).
## Never an intent the rules could accept: SetReady only to the flag it has, GiveUp only outside the
## round or when dead, PickUp only of an item that does not exist or rests FAR_M away, nothing a
## race could turn into an action.

## Of each frame, the chance it sends something.
const ACT_CHANCE := 0.4
## Malformed messages it allows itself within the host's window: under HostSession.MALFORMED_LIMIT.
const MALFORMED_CAP := 40
## The bursts: past the intents bucket (100) and the voice bucket (500) of PeerBudget.
const BURST_INTENTS := 130
const BURST_VOICE := 530
## Voice frames it sends as soon as the silent pregame shows (#213), under the voice bucket so the
## round's burst still meets a full one: nobody may decode them.
const PREGAME_VOICE := 20
## How far an item it names in a PickUp rests from it at least: past the pick-up's 2 m and past
## the over-speed claim's SPEED_M, with a margin; only a carried item moves, and that one is
## unavailable.
const FAR_M := 8.0
## Of the PickUps of a far item, the share sent right after a claim next to it.
const NEAR_CLAIM_CHANCE := 0.5
## Its chaos voice frames count from here (LeakCheck.voice_frame's counter), apart from its bot's.
const VOICE_COUNTER := 500_000

var rng := RandomNumberGenerator.new()
## Intent name -> how many it sent; the malformed shapes and claim shapes sent; for the report.
var sent: Dictionary[String, int] = {}

var _client: BotClient
var _bot: ScenarioBot
var _schema: WireSchema
var _send_raw: Callable
var _budget: ChaosBudget
var _seqs: Array[int] = []
var _next_seq := ChaosFrames.CHAOS_SEQ
var _voice_counter := VOICE_COUNTER
var _claims := 0
var _intent_burst_done := false
var _voice_burst_done := false
var _pregame_voice_done := false


## The chaos of `bot`, whose `client` runs on a chaos transport with `send_raw`; `budget` replays
## the host's malformed count for it (null over ENet: the cap is then kept by its own count).
func _init(
	bot: ScenarioBot,
	client: BotClient,
	schema: WireSchema,
	send_raw: Callable,
	budget: ChaosBudget,
	chaos_seed: int
) -> void:
	_bot = bot
	_client = client
	_schema = schema
	_send_raw = send_raw
	_budget = budget
	rng.seed = chaos_seed


## One frame at host time `now_usec`. `claimed`: its bot's client sent a MoveClaim this frame.
func act(now_usec: int, claimed: bool) -> void:
	if _client.is_ended() or not _client.is_welcomed() or not _is_ready():
		return
	var phase := _client.model.phase
	var life := _client.model.life_of(_bot.peer)
	if phase == &"countdown" and not _intent_burst_done:
		_intent_burst_done = true
		for _i in BURST_INTENTS:
			_send(ChaosFrames.message(_schema, Intents.RETURN_TO_LOBBY, {}, _fresh_seq()))
		return
	if phase == &"pregame" and not _pregame_voice_done:
		_pregame_voice_done = true
		for _i in PREGAME_VOICE:
			_voice()
		return
	if phase == &"round" and life == ClientModel.Life.ALIVE and not _voice_burst_done:
		_voice_burst_done = true
		for _i in BURST_VOICE:
			_voice()
		return
	if rng.randf() >= ACT_CHANCE:
		return
	var roll := rng.randf()
	if roll < 0.45:
		_refused(phase, life, claimed)
	elif roll < 0.65:
		if not claimed:
			_claim()
	elif roll < 0.85:
		_malformed(now_usec, claimed)
	else:
		for _i in rng.randi_range(1, 6):
			_voice()


func _is_ready() -> bool:
	var me: ClientModel.Member = _client.model.roster.get(_bot.peer)
	return me != null and me.ready


## A well-formed intent the rules refuse in `phase` for `life`, as its own client knows them; a
## copy of it now and then (a duplicate), with a fresh, repeated or lower seq. `claimed`: a
## MoveClaim already goes out in this frame.
func _refused(phase: StringName, life: ClientModel.Life, claimed: bool) -> void:
	var choices: Array[StringName] = [
		Intents.SET_READY,
		Intents.CHANGE_SETTINGS,
		Intents.RETURN_TO_LOBBY,
		Intents.LOAD_ACK,
		Intents.PICK_UP,
		Intents.PUT_DOWN,
		Intents.USE,
		Intents.SWAP,
		Intents.STOP_RAISE,
		Intents.RAISE,
		Intents.HELLO,
	]
	if phase != &"round" or life == ClientModel.Life.DEAD:
		# Outside the round, or dead, nothing can turn a GiveUp into a death.
		choices.append(Intents.GIVE_UP)
	var intent := choices[rng.randi_range(0, choices.size() - 1)]
	var seq := _seq_for(intent)
	var args := _args_of(intent)
	var item: int = args.get("item", ChaosOracle.NO_ITEM)
	# Only a resting item is far (FAR_M): a carried one may be next to it, where a claim is a step.
	var resting := (
		item != ChaosOracle.NO_ITEM and _client.model.items[item].holder == ClientModel.NO_HOLDER
	)
	if resting and not claimed and rng.randf() < NEAR_CLAIM_CHANCE:
		_claim_at(ChaosFrames.Claim.NEAR_ITEM, _client.model.items[item].position)
	var packet := ChaosFrames.message(_schema, intent, args, seq)
	_send(packet)
	if rng.randf() < 0.15:
		_send(packet)


func _args_of(intent: StringName) -> Dictionary:
	var args := {}
	match intent:
		Intents.SET_READY:
			args = {"ready": true}
		Intents.CHANGE_SETTINGS:
			args = {"settings": {"packages": 2}}
		Intents.LOAD_ACK:
			args = {"match_id": 1000 + rng.randi_range(0, 999)}
		Intents.PICK_UP:
			args = {"item": _item_to_pick()}
		Intents.PUT_DOWN, Intents.USE:
			args = {"facing": Vector3.FORWARD}
		Intents.RAISE:
			args = {"target": _raise_target()}
		Intents.HELLO:
			args = {"version": WireSchema.VERSION, "content": 0}
	return args


## A chaos seq: mostly the next one; sometimes one sent before (replayed), or one below the last
## (out of order). Hello's is always 0 (its layout has none, §4.3).
func _seq_for(intent: StringName) -> int:
	if intent == Intents.HELLO:
		return 0
	var roll := rng.randf()
	if roll < 0.2 and not _seqs.is_empty():
		return _seqs[rng.randi_range(0, _seqs.size() - 1)]
	if roll < 0.3 and _next_seq > ChaosFrames.CHAOS_SEQ + 2:
		return _next_seq - 2
	return _fresh_seq()


func _fresh_seq() -> int:
	var seq := _next_seq
	_next_seq += 1
	_seqs.append(seq)
	return seq


## The item a PickUp names, as its client knows the items: one resting at least FAR_M from it
## (out_of_reach), one another player carries (unavailable: bot 1's knife, bot 2's package, so
## the two runs of class 8 name what the swapped players hold), or NO_ITEM; NO_ITEM when there is
## no such item.
func _item_to_pick() -> int:
	var far: Array[int] = []
	var carried: Array[int] = []
	for id: int in _client.model.items:
		var item: ClientModel.Item = _client.model.items[id]
		if item.holder != ClientModel.NO_HOLDER and item.holder != _bot.peer:
			carried.append(id)
		elif item.holder == ClientModel.NO_HOLDER and not item.delivered:
			if item.position.distance_to(_bot.position) > FAR_M:
				far.append(id)
	var roll := rng.randf()
	var pool: Array[int] = []
	if roll < 0.4:
		pool = far
	elif roll < 0.7:
		pool = carried
	if pool.is_empty():
		return ChaosOracle.NO_ITEM
	return pool[rng.randi_range(0, pool.size() - 1)]


## Whom a Raise names: any player of the roster, itself included. None of them is ever downed while
## the hostile may send a Raise (only bot 4 is knocked down, and then it may not), so the answer is
## not_downed whatever the target's hidden role: bots 1 and 3 swap roles between the two runs of
## class 8.
func _raise_target() -> int:
	var players: Array[int] = []
	for peer: int in _client.model.roster:
		players.append(peer)
	if players.is_empty():
		return _bot.peer
	return players[rng.randi_range(0, players.size() - 1)]


func _claim() -> void:
	var shape := rng.randi_range(0, ChaosFrames.RANDOM_CLAIMS - 1) as ChaosFrames.Claim
	_claim_at(shape, _bot.position)


func _claim_at(shape: ChaosFrames.Claim, at: Vector3) -> void:
	var packet := ChaosFrames.claim(
		shape, _schema, _client.model.epoch, maxi(_client.last_claim_tick(), 0), at, _claims
	)
	_claims += 1
	_send(packet)


## A malformed frame, while the host's window holds fewer than MALFORMED_CAP of its own; never a
## second LATEST frame NetFrame accepts in a frame that has one (`claimed`), which the LATEST merge
## would supersede before the codec sees it.
func _malformed(now_usec: int, claimed: bool) -> void:
	if _budget != null and _budget.malformed_within(now_usec) >= MALFORMED_CAP:
		return
	if _budget == null and _count_of_malformed() >= MALFORMED_CAP:
		return
	var shape := rng.randi_range(0, ChaosFrames.Shape.size() - 1) as ChaosFrames.Shape
	var packet := ChaosFrames.malformed(shape, rng, _schema, _bot.peer)
	if claimed and packet.frame_valid and packet.lane == NetKindTable.Lane.LATEST:
		return
	_send(packet)


func _voice() -> void:
	var frame := LeakCheck.voice_frame(_bot.peer, _voice_counter)
	_voice_counter += 1
	var fields := {"seq": rng.randi_range(0, 0xFFFF), "opus": frame}
	_send(ChaosFrames.message(_schema, &"VoiceUp", fields))


## Over ENet (no replay of the host's window) it keeps under the cap for the whole run.
func _count_of_malformed() -> int:
	var count := 0
	for label: String in sent:
		if label.begins_with("malformed"):
			count += sent[label]
	return count


func _send(packet: ChaosFrames.Packet) -> void:
	if packet == null:
		push_error("chaos: the encoder refused a chaos message")
		return
	if _send_raw.call(packet) as bool:
		sent[packet.label] = sent.get(packet.label, 0) + 1
