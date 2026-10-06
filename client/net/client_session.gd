class_name ClientSession
extends RefCounted
## What every client runs (ARCHITECTURE §4.6): the host's own over the loopback, a remote one over
## ENet, and every bot. It decodes each message through the codec (§4.4) into a DecodedView (the
## record, when keep_history is on) and a ClientModel (what the client knows now), and sends the
## intents: Hello on connected, the rest with a rising seq, one MoveClaim per client tick, LoadAck
## after loading, and VoiceUp. It never reads core/ state (invariant 2): only what the host sent it
## and its own copy of the game mode.
##
## The owner calls step(now_usec) every frame with a clock in microseconds, like HostSession: the
## transport is polled there, and signals fire from it.
##
## A MoveClaim covers every physics step of the mover since the claim before it, so it reports
## the sprint state and movement input if any of those steps had them, not only the last one
## (#155): the claim of the tick in which a sprinter lets go still says it sprinted and pays for
## that tick, as the host's ledger charges it. Its masks (`sprint_ticks`, `moved_ticks`) repeat
## those flags for each of the last MASK_TICKS client ticks, bit i for client tick client_tick - i,
## every tick a claim covered taking that claim's flags: the LATEST lane delivers only the newest
## claim of a poll, and the host still settles each tick of the ones it superseded as sent.

## The session is over for this client, for `reason`: the reason of a Rejected before Welcome
## (wrong_version, wrong_content, full, joins_closed...), of a Disconnecting (load_deadline), or
## one of the constants below. EndReasons (client/app/) says each in words.
signal ended(reason: StringName)
signal welcomed(own_peer: int)
## Every decoded event, after the model folded it (a bot's script learns from these).
signal event_received(event_name: StringName, fields: Dictionary)
## The host placed this client (Correction): the mover adopts the position and velocity.
signal corrected(position: Vector3, velocity: Vector3)
## A map the host asked for was loaded: its owner instantiates it now, before LoadAck goes out.
signal map_loaded(path: String, scene: PackedScene)
## One frame of a VoiceBatch (M5-4b), in the batch's order: the speaker, the stream's seq (u16,
## renumbered by the host per speaker and listener, running on across talk spurts), the host tick
## it was relayed at, and the frame.
## VoiceViews (client/world/) plays only these (the M5 ADR §3 item 1).
signal voice_received(speaker: int, seq: int, tick: int, opus: PackedByteArray)
## Every decoded snapshot, after the model folded it, older ones included (SnapshotBuffer keeps
## them by host tick, §4.7): the host tick it was taken at and its avatars (peer -> fields).
signal snapshot_received(tick: int, avatars: Dictionary)
## A MoveClaim went out: its epoch and client tick, the client ticks the host settles for it
## (`covered`: 1 for the first claim after the Welcome or a placement, which the host takes as one
## tick), its latched sprint flag, and whether it moved itself as the host's stamina counts it
## (movement input and horizontal travel from the last claim's position beyond MOVE_EPSILON).
## PredictedStamina settles the same ticks with the same flags, and the SelfStatus that names this
## claim's tick answers it (#155).
signal claim_sent(epoch: int, tick: int, covered: int, sprint: bool, moved_itself: bool)

const HOST_LOST := &"host_lost"
const CONNECT_FAILED := &"connect_failed"
## LoadMatch named a map that the client's own mode does not list: it never loads a path from the
## wire alone (§4.5).
const UNKNOWN_MAP := &"unknown_map"
const LOAD_FAILED := &"load_failed"
## The owner left (leave()).
const LEFT := &"left"
## MoveClaim's jumps is a u16 (§4.3); a count that high never happens in one epoch.
const MAX_JUMPS := 0xFFFF
## The events that move this client right before its Correction (place_players.gd at Loading and
## at End -> Lobby, life_rules.gd at a knockdown and a respawn; a death and a revive send none):
## that Correction counts in `placements`, not in `corrections`. A new rule that places a player
## and sends a Correction adds its event here.
const PLACING_EVENTS: Array[StringName] = [&"PlayersPlaced", &"KnockedDown", &"Respawned"]
## Horizontal travel in one claim that counts as moving, for stamina: the host's
## `MovementRule.MOVE_EPSILON`.
const MOVE_EPSILON := 0.0001
## The client ticks a claim's masks describe: `MovementRule.MASK_TICKS`, the wire's u32.
const MASK_TICKS := 32

## The record of every decoded message, for the bots and the leak test; off by default (a real
## client does not need it, and a 10-minute match holds 12000 snapshots), like Match.keep_history.
var keep_history := false
## False for a bot: it acknowledges LoadMatch without loading the scene (§4.6).
var load_levels := true
var view := DecodedView.new()
var model: ClientModel
## Why the session ended; empty while it runs.
var end_reason: StringName = &""
## Payloads the codec rejected (the transport has counted what NetFrame rejected).
var bad_payloads := 0
## The Corrections the host sent because it refused this client's claims (the debug overlay shows
## it for #76's tuning; honest play gets none). A placement's, a knockdown's or a respawn's is not
## counted here.
var corrections := 0
## The Corrections that came with a placement, a knockdown or a respawn of this client
## (PLACING_EVENTS): the host moved it; nothing it claimed was refused.
var placements := 0

var _transport: NetTransport
var _schema: WireSchema
var _mode: GameMode
var _content := 0
## The seq of the last intent sent; Hello's is 0.
var _seq := 0
var _voice_seq := 0
var _welcomed := false
var _clock_start := -1
var _last_claim_tick := -1
var _jumps := 0
var _position := Vector3.ZERO
var _velocity := Vector3.ZERO
var _facing := Vector3.FORWARD
## The sprint state and the movement input of any step set_motion reported since the last claim.
var _sprint := false
var _moving := false
## The last claim's masks: bit i says whether client tick last_claim_tick() - i had the sprint
## state (_sprint_history), or the player's own movement (_moved_history), by the claim covering it.
var _sprint_history := 0
var _moved_history := 0
## Where the last claim went, or where the host put the client (Welcome, a Correction): the next
## claim's travel is measured from it, as the host measures from its last accepted position.
var _claimed_position := Vector3.ZERO
## The next claim is the first after the Welcome or a placement: the host counts it as one tick.
var _fresh := true
var _on_floor := true
## The map being loaded and the match it is for; empty when nothing loads.
var _loading := ""
var _loading_match := -1
## Threaded loads nobody waits for any more (the session ended, or a newer LoadMatch replaced
## them): each is collected once it is done, or ResourceLoader would keep its scene for good.
var _abandoned := PackedStringArray()
## The reason of the last Disconnecting: the end reason when the host then disconnects it.
var _disconnecting: StringName = &""
## True from a placing event naming this client until the Correction that follows it.
var _placement_due := false


## `transport` joins (or is the host's own client of) a host whose table is `schema`'s; `mode` is
## the client's own copy of the game mode, whose ContentFingerprint Hello carries.
func _init(transport: NetTransport, mode: GameMode, schema: WireSchema = null) -> void:
	_transport = transport
	_mode = mode
	_schema = schema if schema != null else WireSchema.game(OS.is_debug_build())
	_content = content_of(mode)
	model = ClientModel.new(mode)
	_transport.connected.connect(_on_connected)
	_transport.connect_failed.connect(_end)
	_transport.host_lost.connect(_on_host_lost)
	_transport.packet_received.connect(_on_packet)
	corrected.connect(_count_correction)
	event_received.connect(_note_placement)


## The content hash Hello carries for `mode`: a code host's `open` and a joiner's version check
## against the service's `found` use the same (the M6 design §2.5).
static func content_of(mode: GameMode) -> int:
	return ContentFingerprint.of(ContentHash.of(mode), mode.lobby_level, mode.maps)


## Polls the transport, then advances a threaded load and sends the MoveClaim due by `now_usec`.
func step(now_usec: int) -> void:
	if _clock_start < 0:
		_clock_start = now_usec
	_collect_abandoned()
	if is_ended():
		return
	_transport.poll()
	if is_ended():
		return
	_advance_load()
	_claim(now_usec)


func is_welcomed() -> bool:
	return _welcomed


func is_ended() -> bool:
	return not end_reason.is_empty()


## The own connection's kind (the M6 design §3 item 4, #431): its own transport's, never another
## peer's; the debug overlay shows it. LOCAL for the host's own client.
func route() -> NetTransport.Route:
	return _transport.own_route()


## The own round trip to the host in ms, -1 when none is measured (see set_measuring_round_trip).
func round_trip_ms() -> int:
	return _transport.own_round_trip_ms()


## Has the own transport measure the round trip where that costs traffic (WebRTC's pings): the
## debug overlay turns it on while it shows.
func set_measuring_round_trip(on: bool) -> void:
	_transport.measure_round_trip = on


func is_measuring_round_trip() -> bool:
	return _transport.measure_round_trip


## The client tick at `now_usec`: 20 Hz core ticks of this client's own clock (Ticks.RATE),
## counted from its first step.
func client_tick(now_usec: int) -> int:
	if _clock_start < 0:
		return 0
	@warning_ignore("integer_division")
	return (now_usec - _clock_start) * Ticks.RATE / 1000000


## The client tick of the last MoveClaim sent; -1 before the first.
func last_claim_tick() -> int:
	return _last_claim_tick


## What the next MoveClaim says, from the mover (the player controller or a bot's), once per
## physics step: the last call's position, velocity, facing and floor, and the sprint state and
## movement input if any call since the last claim had them (#155).
func set_motion(
	position: Vector3,
	velocity: Vector3,
	facing: Vector3,
	sprint: bool,
	moving: bool,
	on_floor: bool
) -> void:
	_position = position
	_velocity = velocity
	_facing = facing
	_sprint = _sprint or sprint
	_moving = _moving or moving
	_on_floor = on_floor


## What the next MoveClaim says as the facing, when the mover turned outside its physics step
## (a respawn looks level, #191); the rest of set_motion's report stays.
func set_facing(facing: Vector3) -> void:
	_facing = facing


## The mover jumped: the claims' count of jumps in this epoch rises (E2).
func count_jump() -> void:
	_jumps = mini(_jumps + 1, MAX_JUMPS)


## The jumps counted since the client adopted its epoch.
func jumps() -> int:
	return _jumps


## Sends an intent with the next seq, its fields as the MatchCommand's args; returns the seq, or -1
## when it could not be sent (not connected, or the codec refused it and logged why).
func send_intent(intent: StringName, args: Dictionary = {}) -> int:
	var seq := _seq + 1
	if _send(WireMessage.new(intent, args, seq)) != OK:
		return -1
	_seq = seq
	return seq


## Debug builds only (E17): forces `role` on `peer` for the deals that follow; "" clears it. Only
## the host's own client may send it; the host drops it from anyone else.
func force_role(peer: int, role: String) -> int:
	var seq := _seq + 1
	if _send(WireMessage.new(&"ForceRole", {"role": role}, seq, peer)) != OK:
		return -1
	_seq = seq
	return seq


## Debug builds only (E17): forces the match clocks that start from now on to `seconds` instead
## of the match duration setting; 0 clears it. `peer` is the sender's own id (the host's own
## player), which the debug kind names. The bot scenarios' `clock_s` (M4-3).
func force_clock(peer: int, seconds: int) -> int:
	var seq := _seq + 1
	if _send(WireMessage.new(&"ForceClock", {"seconds": seconds}, seq, peer)) != OK:
		return -1
	_seq = seq
	return seq


## Sends one 20 ms Opus frame; the host relays it to whoever may hear this client.
func send_voice(opus: PackedByteArray) -> Error:
	var sent := _send(WireMessage.new(&"VoiceUp", {"seq": _voice_seq, "opus": opus}))
	if sent == OK:
		_voice_seq = (_voice_seq + 1) & 0xFFFF
	return sent


## Leaves the session (the owner's choice, not a failure).
func leave() -> void:
	_end(LEFT)


## The threaded loads it still has to collect; step() collects each once it is done.
func abandoned_loads() -> PackedStringArray:
	return _abandoned


func _notification(what: int) -> void:
	# Freed before step() collected them: wait for each here, once, so none stays in ResourceLoader.
	if what == NOTIFICATION_PREDELETE:
		for path: String in _abandoned:
			var status := ResourceLoader.load_threaded_get_status(path)
			if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				ResourceLoader.load_threaded_get(path)
		_abandoned.clear()


func _on_host_lost() -> void:
	_end(HOST_LOST if _disconnecting.is_empty() else _disconnecting)


func _on_connected(_own_id: int) -> void:
	var hello := {"version": WireSchema.VERSION, "content": _content}
	_send(WireMessage.new(&"Hello", hello))


func _on_packet(_from_peer: int, kind: int, payload: PackedByteArray) -> void:
	if is_ended():
		return
	var message := _schema.decode(kind, payload)
	if message == null:
		bad_payloads += 1
		if bad_payloads == 1:
			push_warning("client: a message of kind %d from the host did not decode" % kind)
		return
	if keep_history:
		view.record(message)
	if message.name == DecodedView.SNAPSHOT:
		_on_snapshot(message.fields)
	elif message.name == DecodedView.VOICE_BATCH:
		for down: WireMessage in DecodedView.voice_downs(message):
			voice_received.emit(
				down.fields["speaker"] as int,
				down.fields["seq"] as int,
				down.fields["tick"] as int,
				down.fields["opus"] as PackedByteArray
			)
	else:
		_on_event(message.name, message.fields)


func _on_event(event_name: StringName, fields: Dictionary) -> void:
	if not _welcomed and event_name == &"Rejected":
		# E14's client rule: before Welcome, any Rejected ends the join with its reason.
		event_received.emit(event_name, fields)
		_end(fields["reason"] as StringName)
		return
	model.fold(event_name, fields)
	match event_name:
		&"Welcome":
			_welcomed = true
			view.peer = model.own_peer
			_fresh = true
			_adopt(fields["spot"] as Vector3, Vector3.ZERO)
			welcomed.emit(model.own_peer)
		&"Correction":
			_adopt(fields["position"] as Vector3, fields["velocity"] as Vector3)
			corrected.emit(_position, _velocity)
		&"LoadMatch":
			_start_load(fields["match_id"] as int, fields["map"] as String)
	if event_name == &"Disconnecting":
		# #119 (E21): the host disconnects this client next; that ends it with this reason.
		_disconnecting = fields["reason"]
	event_received.emit(event_name, fields)


## A snapshot: folded into the model, then handed to whoever draws the others (M4-7).
func _on_snapshot(fields: Dictionary) -> void:
	model.fold_snapshot(fields)
	snapshot_received.emit(fields["tick"] as int, fields["avatars"] as Dictionary)


func _count_correction(_position: Vector3, _velocity: Vector3) -> void:
	if _placement_due:
		_placement_due = false
		placements += 1
		_fresh = true
	else:
		corrections += 1


## A placing event that names this client: the next Correction is its placement (the host sends
## the event first, place_players.gd and life_rules.gd).
func _note_placement(event_name: StringName, fields: Dictionary) -> void:
	if not PLACING_EVENTS.has(event_name) or not _welcomed:
		return
	if event_name == &"PlayersPlaced":
		_placement_due = (fields["spots"] as Dictionary).has(model.own_peer)
	elif fields["peer"] as int == model.own_peer:
		_placement_due = true


## A new epoch (Welcome, Correction): its claims count jumps from 0 and start where the host put it,
## and the steps before it no longer count for the next claim's flags.
func _adopt(position: Vector3, velocity: Vector3) -> void:
	_jumps = 0
	_position = position
	_velocity = velocity
	_claimed_position = position
	_sprint = false
	_moving = false


## One MoveClaim per client tick, and only while the phase accepts one from this client.
func _claim(now_usec: int) -> void:
	if not _welcomed or not _claims_accepted():
		return
	var tick := client_tick(now_usec)
	if tick <= _last_claim_tick:
		return
	var covered := 1 if _fresh or _last_claim_tick < 0 else tick - _last_claim_tick
	var travel := Vector2(_position.x - _claimed_position.x, _position.z - _claimed_position.z)
	var moved_itself := _moving and travel.length() > MOVE_EPSILON
	var since := MASK_TICKS if _last_claim_tick < 0 else tick - _last_claim_tick
	var sprint_ticks := _shifted(_sprint_history, since, _sprint)
	var moved_ticks := _shifted(_moved_history, since, moved_itself)
	var claim := {
		"epoch": model.epoch,
		"client_tick": tick,
		"position": _position,
		"velocity": _velocity,
		"facing": _facing,
		"sprint": _sprint,
		"moving": _moving,
		"on_floor": _on_floor,
		"jumps": _jumps,
		"sprint_ticks": sprint_ticks,
		"moved_ticks": moved_ticks,
	}
	if _send(WireMessage.new(Intents.MOVE_CLAIM, claim)) != OK:
		return
	var sprint := _sprint
	_last_claim_tick = tick
	_claimed_position = _position
	_sprint_history = sprint_ticks
	_moved_history = moved_ticks
	_fresh = false
	_sprint = false
	_moving = false
	claim_sent.emit(model.epoch, tick, covered, sprint, moved_itself)


## `mask` moved on by `ticks` client ticks, each of which takes `flag`, cut to MASK_TICKS bits.
static func _shifted(mask: int, ticks: int, flag: bool) -> int:
	var all := (1 << MASK_TICKS) - 1
	if ticks >= MASK_TICKS:
		return all if flag else 0
	var added := (1 << ticks) - 1 if flag else 0
	return ((mask << ticks) | added) & all


## Whether the client sends MoveClaims now (its own copy of the phase and its own life).
func claims_accepted() -> bool:
	return _welcomed and _claims_accepted()


## Whether the client's own copy of the current phase accepts MoveClaim from it (§4.3): as a
## player, living or downed, and the host's own player as peer 1; never while dead (the dead send
## no intents, and the host accepts none from them).
func _claims_accepted() -> bool:
	var spec := model.phase_spec()
	if spec == null:
		return false
	var life := model.life_of(model.own_peer)
	if life != ClientModel.Life.ALIVE and life != ClientModel.Life.DOWNED:
		return false
	var mine: int = AcceptSpec.From.PLAYER
	mine |= AcceptSpec.From.LIVING if life == ClientModel.Life.ALIVE else AcceptSpec.From.DOWNED
	if model.own_peer == NetTransport.HOST_ID:
		mine |= AcceptSpec.From.HOST
	return (spec.senders_of(Intents.MOVE_CLAIM) & mine) != 0


func _start_load(match_id: int, map: String) -> void:
	if not _mode.maps.has(map):
		_end(UNKNOWN_MAP)
		return
	_loading_match = match_id
	if not load_levels:
		send_intent(Intents.LOAD_ACK, {"match_id": match_id})
		return
	_abandon_load()
	var abandoned := _abandoned.find(map)
	if abandoned >= 0:
		# The same map is still loading for an earlier LoadMatch: take that request over.
		_abandoned.remove_at(abandoned)
	elif ResourceLoader.load_threaded_request(map, "PackedScene") != OK:
		_end(LOAD_FAILED)
		return
	_loading = map


func _advance_load() -> void:
	if _loading.is_empty():
		return
	var status := ResourceLoader.load_threaded_get_status(_loading)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var path := _loading
	_loading = ""
	var scene: PackedScene = null
	if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		# A failed load is collected too, or ResourceLoader would keep its task.
		scene = ResourceLoader.load_threaded_get(path) as PackedScene
	if scene == null:
		_end(LOAD_FAILED)
		return
	map_loaded.emit(path, scene)
	if not is_ended():
		send_intent(Intents.LOAD_ACK, {"match_id": _loading_match})


## The load in flight, if any, is no longer waited for.
func _abandon_load() -> void:
	if not _loading.is_empty():
		_abandoned.append(_loading)
		_loading = ""


func _collect_abandoned() -> void:
	for i in range(_abandoned.size() - 1, -1, -1):
		var path := _abandoned[i]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(path)
		_abandoned.remove_at(i)


func _send(message: WireMessage) -> Error:
	if is_ended():
		return ERR_UNAVAILABLE
	var payload := _schema.encode(message)
	if payload.is_empty():
		return ERR_INVALID_DATA
	return _transport.send(NetTransport.HOST_ID, _schema.kind_of(message.name), payload)


func _end(reason: StringName) -> void:
	if is_ended():
		return
	end_reason = reason
	_abandon_load()
	_transport.close()
	ended.emit(reason)
