class_name ChaosFrames
extends RefCounted
## What a modified client can put on the wire, each input built so that the host's answer is known
## from ARCHITECTURE alone (§4 Transport, §4.3 the wire types, §4.4 the codec, §4.5 the session):
## - malformed frames (Shape): NetFrame's rejects (too short, too large, an unknown kind, random
##   bytes behind one, the wrong direction or lane, a payload over its kind's cap, truncated,
##   trailing bytes) and the codec's (a bool that is not 0 or 1, an item 0xFFFF, a peer 0, a NaN or
##   infinite float, unknown flag bits, an id with a capital letter, bytes after the last field, an
##   empty Opus frame), and the debug kinds (ForceRole, kind 28; ForceClock, kind 29, one second)
##   from a peer other than 1, which the host counts as bad payloads (E17); and NextStage's (kind
##   15, #599): 0 to 3 bytes where its seq goes (the codec's bad payload), and its seq with 1 to 4
##   bytes after it (over the row's cap of 4, NetFrame's payload too large); and Interact's (kind
##   18, #796, #770): its seq and 0 to 3 of its 4 field bytes (the codec's), and its seq, station
##   and item with 1 to 4 bytes after them (over the cap of 8). Since #770 its station and item
##   may each be none (0xFFFF), so no value of them is malformed: a station or item that names
##   nothing, or both or neither, is the rules' (ChaosOracle).
##   Each Packet names the NetRejects reason it must be counted under
##   (`expect`);
## - well-formed intents (message()), whose answer the rules give (ChaosOracle);
## - hostile MoveClaims (Claim), tagged in their velocity so the host's observer can tell them from
##   the bot's own claims: a teleport, a speed over the cap, a client tick far past the credit, an
##   overflowing jumps counter, another epoch, a client tick that does not rise.
## A malformed payload is built from the encoder's own valid bytes, then broken in one place.

## The malformed shapes. RANDOM_BYTES: random bytes behind an unassigned kind byte.
enum Shape {
	TOO_SHORT,
	TOO_LARGE,
	UNKNOWN_KIND,
	RANDOM_BYTES,
	WRONG_DIRECTION,
	WRONG_LANE,
	OVER_CAP,
	TRUNCATED,
	TRAILING,
	BAD_BOOL,
	BAD_ITEM,
	BAD_PEER,
	NAN_CLAIM,
	INF_CLAIM,
	FLAG_BITS,
	BAD_ID,
	CODEC_TRAILING,
	EMPTY_OPUS,
	DEBUG_KIND,
	DEBUG_CLOCK,
	NEXT_STAGE_NO_SEQ,
	NEXT_STAGE_TRAILING,
	SET_PROFILE_NO_COLOUR,
	SET_PROFILE_TRAILING,
	SET_PROFILE_BAD_NAME,
	INTERACT_TRUNCATED,
	INTERACT_TRAILING,
}

## The hostile MoveClaims. STALE_TICK repeats a client tick the host already has: dropped, or, as
## the first claim of a new baseline, checked as one tick and corrected (§7.1; both allowed).
## NEAR_ITEM claims the position it is given (an item resting far away, ahead of a PickUp of it):
## not one of the random shapes (RANDOM_CLAIMS), its caller picks the item.
## WALK is a step a living walk covers in one client tick: the knocked-down hostile sends it, and
## the host takes only its look and corrects none (KE4); not a random shape either.
enum Claim { TELEPORT, SPEED, FUTURE_TICK, JUMPS, OTHER_EPOCH, STALE_TICK, NEAR_ITEM, WALK }

## The chaos intents' seqs start here: an honest client's own seqs stay far below, so a Rejected
## names which intent it answers.
const CHAOS_SEQ := 1_000_000
## A chaos MoveClaim's velocity.y is CLAIM_TAG plus its Claim shape: no honest claim moves at
## 1000 m/s upwards, and the velocity is never checked (§7.1), only relayed once accepted.
const CLAIM_TAG := 1000.0
## How far a teleport goes, and how far the over-speed claim goes in one client tick (more than
## a sprint with the push allowance covers in several ticks, §7.1).
const TELEPORT_M := 80.0
const SPEED_M := 6.0
## How far the walking claim goes in one client tick: less than a walk covers (§7.1).
const WALK_M := 0.1
## How far past its last claim a "future" client tick goes: past MAX_TICK_CREDIT (200 ticks).
const FUTURE_TICKS := 5000
## The Claim shapes a chaos peer draws at random: the ones before NEAR_ITEM.
const RANDOM_CLAIMS := Claim.NEAR_ITEM
## Kinds no row of the table has (0 is the transport's ADMIT, never a client's). 15 left it when
## NextStage took it (#599), 16 took its place; 16 and 66 left it when SetProfile and
## ProfileChanged took them (#551), 17 and 67 took theirs; 17 and 67 left it when release/m7's
## Throw and ZoneProgress took them (#837, ItemThrown took 68), 18 and 69 took theirs; 18 left it
## when Interact took it (#796), 20 took its place; 69 left it when ItemVanished took it (#779), 70
## took its place; 70 left it when SwitchChanged took it (#797, ButtonPressed took 71), 72 took its
## place; 72 left it when ItemChanged took it (#771), 73 took its place; 73 left it when OrderPosted
## took it (#772, HerbsDealt took 74), 75 took its place; 75 left it when LiftChanged took it (#807,
## PartNeeded took 76), 77 took its place; 77 left it when FilmLoaded took it (#781, ShotTaken took
## 78), 79 took its place; 79 and 80 left it when GrillLoaded and IngredientPlaced took them
## (#773), 81 and 82 took their places; 81 and 82 left it when FitChanged and PartFitted took them
## (#808), 83 and 84 took theirs; 83 and 84 left it when PhotoPrinted and PhotoHung took them
## (#782), 85 and 86 took theirs; 85 and 86 left it when BurgerPlated and BurgerServed took them
## (#1101), 87 and 88 took theirs; 20 left it when Pose took it (#1296), 21 took its place; 21
## left it when HandOver took it (#1389), 22 took its place; 22, 23, 87 and 88 left it when
## TakeOffer, CancelOffer, OfferMade and OfferEnded took them (#1434), 89 and 90 took theirs;
## UseSecondary took 24 and the debug kinds moved to 28 and 29 (#1438): 26 and 31 stay free; 89
## and 90 left it when EngineProblemOpened and EngineProblemFixed took them (#1453), 92 and 93
## took theirs; 92, 93 and 95 left it when GillFlipped, BreakerChain and CrystalChanged took them
## (#1461); WheelPose took 26 (#1485), 27 took its place.
const UNASSIGNED: Array[int] = [0, 27, 31, 97, 111, 113, 127, 128, 200, 255]
## The host-to-client kinds a chaos peer sends the host (Shape.WRONG_DIRECTION, NetFrame's
## `wrong_direction`), one drawn per packet: Rejected, the Generator's events (#797) and the car
## repair's (#807, #808), the photo task's (#781, #782), the cooking task's (#773, #1101) and the
## ship engine's (#1453) and the pinball's (#1398), each with valid fields.
const WRONG_DIRECTION: Array[StringName] = [
	&"Rejected",
	&"SwitchChanged",
	&"ButtonPressed",
	&"LiftChanged",
	&"PartNeeded",
	&"FilmLoaded",
	&"ShotTaken",
	&"GrillLoaded",
	&"IngredientPlaced",
	&"FitChanged",
	&"PartFitted",
	&"PhotoPrinted",
	&"PhotoHung",
	&"BurgerPlated",
	&"BurgerServed",
	&"EngineProblemOpened",
	&"EngineProblemFixed",
	&"EngineBlast",
	&"GillFlipped",
	&"BreakerChain",
	&"CrystalChanged",
	&"PinballState",
	&"BoothStep",
]
const WRONG_DIRECTION_FIELDS: Dictionary[StringName, Dictionary] = {
	&"Rejected": {"seq": CHAOS_SEQ, "reason": &"not_accepted"},
	&"SwitchChanged": {"station": 1, "on": true},
	&"ButtonPressed": {"station": 1},
	&"LiftChanged": {"station": 1, "up": true, "tick": 1},
	&"EngineProblemOpened": {"problem": 1, "stations": [1, 2], "deadline": 40},
	&"EngineProblemFixed": {"problem": 1},
	&"EngineBlast": {"stage": 1},
	&"GillFlipped": {"station": 1, "slit": 2, "open": true},
	&"BreakerChain": {"problem": 1, "breakers": [3, 5], "next": 1, "since": 40},
	&"CrystalChanged": {"station": 2, "charger": 4, "phase": 2, "item": 1, "tick": 200},
	&"PinballState":
	{
		"game": 1,
		"player": 2,
		"left": true,
		"right": false,
		"in_play": true,
		"score": 500,
		"balls_left": 2,
		"best": 1200,
		"best_name": "Chaos",
	},
	&"BoothStep":
	{
		"station": 1,
		"strip": 2,
		"step": 1,
		"presser": 0,
		"frames": 0,
		"countdown": 0,
		"gap": 0,
		"frame": 1,
		"record": [],
		"items": [],
	},
	&"PartNeeded": {"station": 1, "kind": &"part"},
	&"FilmLoaded": {"station": 1, "item": 1},
	&"GrillLoaded": {"station": 1, "item": 1, "fried": 2, "burnt": 3},
	&"IngredientPlaced": {"item": 1, "station": 1},
	&"BurgerPlated":
	{"item": 1, "station": 1, "bun": &"bun_white", "patty": &"patty_beef", "herb": &"herb_mint"},
	&"BurgerServed": {"station": 1, "right": true},
	&"PhotoPrinted": {"item": 1, "shot": 0},
	&"PhotoHung": {"item": 1, "station": 1, "counted": true},
	&"ShotTaken":
	{
		"station": 1,
		"film": 1,
		"shot": 0,
		"record":
		[
			{
				"peer": 2,
				"position": Vector3.ZERO,
				"facing": Vector3.FORWARD,
				"downed": false,
				"crouched": false,
				"held_item": -1,
				"belt_item": 1,
				"belt_item2": -1,
			}
		],
	},
	&"FitChanged": {"station": 1, "fitter": 2, "tick": 1},
	&"PartFitted": {"station": 1, "item": 1},
}
## The facings a hostile Throw carries (kind 17, §4.6.5.3): a plain unit facing, and the finite
## ones ThrowItem.unit_facing cannot normalize, so the host falls back on the last accepted claim's:
## zero, and two whose squared length underflows (1e-30) or overflows (1e38) in single precision.
## Finite on purpose: a NaN or infinite float is class 1, which the codec refuses before any rule.
## Round takes Throw from the living (#646): with the hostile's empty hand each is refused
## `empty_hand` there, `not_accepted` elsewhere.
const THROW_FACINGS: Array[Vector3] = [
	Vector3.FORWARD, Vector3.ZERO, Vector3(1e-30, 0, 0), Vector3(1e38, 0, 0)
]
## MoveClaim's layout (§4.3), its RELIABLE twin's too: the first float of position, velocity and
## facing, and the flags (jumps, sprint_ticks and moved_ticks follow them).
const CLAIM_FLOATS_AT := 8
const CLAIM_FLOATS := 9
const CLAIM_FLAGS_AT := 44
## A hostile claim's per-tick masks (#155): no tick sprinted (sprint_ticks 0) and every tick moved
## by the player itself, as ClientSession sends them for a player that walked each tick. A claim
## that sends no masks gets the same from its flags (MovementRule), so each Claim shape means what
## it meant before the masks.
const HONEST_MOVED_TICKS := MovementRule.MAX_MASK


## One packet a chaos peer sends, with what the host must make of it.
class Packet:
	extends RefCounted
	var bytes := PackedByteArray()
	var channel := 0
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
	## The lane the host takes it on when NetFrame accepts it (the budgets are per lane, §4.5).
	var lane := NetKindTable.Lane.RELIABLE
	## NetFrame accepts it, so a budget is taken for it whatever its payload holds.
	var frame_valid := true
	## The reason the host counts it under: NONE for a message that decodes (the rules answer it).
	var expect := NetRejects.Reason.NONE
	## What it is, for a failure's report ("malformed BAD_BOOL", "intent PickUp", "honest").
	var label := ""
	## The intent or message it carries when it decodes, and its seq.
	var intent: StringName = &""
	var seq := -1

	func payload_size() -> int:
		return bytes.size() - NetFrame.HEADER_BYTES


## A packet that frames `payload` as `kind` on `lane`, the way an honest client sends it.
static func framed(kind: int, payload: PackedByteArray, lane: NetKindTable.Lane) -> Packet:
	var packet := Packet.new()
	packet.bytes = NetFrame.encode(kind, payload)
	packet.lane = lane
	packet.channel = NetKindTable.channel_of(lane)
	packet.mode = NetKindTable.mode_of(lane)
	return packet


## A well-formed message: `name` with `fields` (and `seq`, ForceRole's `peer`) as the encoder writes
## it; null when the encoder refuses it.
static func message(
	schema: WireSchema, name: StringName, fields: Dictionary, seq := 0, peer := 0
) -> Packet:
	var payload := schema.encode(WireMessage.new(name, fields, seq, peer))
	if payload.is_empty():
		return null
	var kind := schema.kind_of(name)
	var packet := framed(kind, payload, schema.row(kind).lane)
	packet.intent = name
	packet.seq = seq
	packet.label = "intent %s" % name
	return packet


## A malformed packet of `shape` from a client whose own peer id is `own`.
static func malformed(
	shape: Shape, rng: RandomNumberGenerator, schema: WireSchema, own: int
) -> Packet:
	var packet: Packet
	if shape <= Shape.TRAILING or shape in [Shape.NEXT_STAGE_TRAILING, Shape.INTERACT_TRAILING]:
		packet = _bad_frame(shape, rng, schema)
	else:
		packet = _bad_payload(shape, rng, schema, own)
	packet.label = "malformed %s" % Shape.find_key(shape)
	return packet


## A hostile MoveClaim of `shape` from a player standing at `at` in `epoch`, whose last claim
## carried `last_tick`; `index` makes its tag unique. NEAR_ITEM claims `at` itself, which its
## caller sets to a point far from where the player stands. `facing` is the claim's facing.
static func claim(
	shape: Claim,
	schema: WireSchema,
	epoch: int,
	last_tick: int,
	at: Vector3,
	index: int,
	facing := Vector3.FORWARD,
) -> Packet:
	var position := at + Vector3(TELEPORT_M, 0.0, 0.0)
	var tick := last_tick + 1
	var claimed_epoch := epoch
	var jumps := 0
	match shape:
		Claim.SPEED:
			position = at + Vector3(0.0, 0.0, SPEED_M)
		Claim.WALK:
			position = at + Vector3(0.0, 0.0, WALK_M)
		Claim.NEAR_ITEM:
			position = at
		Claim.FUTURE_TICK:
			tick = last_tick + FUTURE_TICKS
		Claim.JUMPS:
			# Where it stands: only the count can call for the Correction (a rise d of jumps
			# above the ticks the claim covers, and stamina for d jumps, §7.1).
			position = at
			jumps = ClientSession.MAX_JUMPS
		Claim.OTHER_EPOCH:
			claimed_epoch = epoch + 1 + index % 3 if index % 2 == 0 or epoch == 0 else epoch - 1
		Claim.STALE_TICK:
			tick = maxi(0, last_tick - index % 3)
	var fields := {
		"epoch": claimed_epoch,
		"client_tick": tick,
		"position": position,
		"velocity": Vector3(float(index % 997), CLAIM_TAG + shape, 0.0),
		"facing": facing,
		"sprint": false,
		"moving": true,
		"on_floor": true,
		"crouched": false,
		"sneaking": false,
		"jumps": jumps,
		"sprint_ticks": 0,
		"moved_ticks": HONEST_MOVED_TICKS,
	}
	var packet := message(schema, Intents.MOVE_CLAIM, fields)
	packet.label = "claim %s" % Claim.find_key(shape)
	return packet


## The Claim shape of a chaos MoveClaim's args, or -1 for a claim without the tag (an honest one).
static func claim_shape(args: Dictionary) -> int:
	var velocity: Variant = args.get("velocity")
	if not velocity is Vector3 or (velocity as Vector3).y < CLAIM_TAG:
		return -1
	return roundi((velocity as Vector3).y - CLAIM_TAG)


static func _bad_frame(shape: Shape, rng: RandomNumberGenerator, schema: WireSchema) -> Packet:
	var ready := schema.encode(WireMessage.new(&"SetReady", {"ready": true}, CHAOS_SEQ))
	var set_ready := schema.kind_of(&"SetReady")
	var packet := framed(set_ready, ready, NetKindTable.Lane.RELIABLE)
	packet.frame_valid = false
	match shape:
		Shape.TOO_SHORT:
			packet.bytes = _random_bytes(rng, rng.randi_range(0, NetFrame.HEADER_BYTES - 1))
			packet.expect = NetRejects.Reason.TOO_SHORT
		Shape.TOO_LARGE:
			var big := _random_bytes(rng, NetFrame.MAX_PACKET_BYTES + 1 + rng.randi_range(0, 64))
			big[0] = set_ready
			packet.bytes = big
			packet.expect = NetRejects.Reason.TOO_LARGE
		Shape.UNKNOWN_KIND:
			var payload := _random_bytes(rng, rng.randi_range(0, 40))
			packet.bytes = NetFrame.encode(_unassigned(rng), payload)
			packet.expect = NetRejects.Reason.UNKNOWN_KIND
		Shape.RANDOM_BYTES:
			var noise := _random_bytes(rng, rng.randi_range(NetFrame.HEADER_BYTES, 120))
			noise[0] = _unassigned(rng)
			packet.bytes = noise
			packet.expect = NetRejects.Reason.UNKNOWN_KIND
		Shape.WRONG_DIRECTION:
			var wrong: StringName = WRONG_DIRECTION[rng.randi_range(0, WRONG_DIRECTION.size() - 1)]
			var payload := schema.encode(WireMessage.new(wrong, WRONG_DIRECTION_FIELDS[wrong]))
			packet.bytes = NetFrame.encode(schema.kind_of(wrong), payload)
			packet.expect = NetRejects.Reason.WRONG_DIRECTION
		Shape.WRONG_LANE:
			# A reliable intent on the voice channel, unreliable.
			packet.channel = NetKindTable.channel_of(NetKindTable.Lane.VOICE)
			packet.mode = NetKindTable.mode_of(NetKindTable.Lane.VOICE)
			packet.expect = NetRejects.Reason.WRONG_LANE
		Shape.OVER_CAP:
			var over := ready.duplicate()
			over.append(rng.randi_range(0, 255))
			packet.bytes = NetFrame.encode(set_ready, over)
			packet.expect = NetRejects.Reason.PAYLOAD_TOO_LARGE
		Shape.TRUNCATED:
			packet.bytes = packet.bytes.slice(0, packet.bytes.size() - rng.randi_range(1, 4))
			packet.expect = NetRejects.Reason.TRUNCATED
		Shape.TRAILING:
			var longer := packet.bytes.duplicate()
			longer.append_array(_random_bytes(rng, rng.randi_range(1, 4)))
			packet.bytes = longer
			packet.expect = NetRejects.Reason.TRAILING_BYTES
		Shape.NEXT_STAGE_TRAILING:
			# NextStage's seq with bytes after it, declared in full: a valid payload is exactly
			# the row's cap, so NetFrame refuses it before the codec could see the extra bytes.
			var next_stage := schema.encode(WireMessage.new(&"NextStage", {}, CHAOS_SEQ))
			next_stage.append_array(_random_bytes(rng, rng.randi_range(1, 4)))
			packet.bytes = NetFrame.encode(schema.kind_of(&"NextStage"), next_stage)
			packet.expect = NetRejects.Reason.PAYLOAD_TOO_LARGE
		Shape.INTERACT_TRAILING:
			# Interact (seq, station, item) with bytes after it: at the row's cap, as
			# NEXT_STAGE_TRAILING.
			var fields := _interact_fields(rng)
			var interact := schema.encode(WireMessage.new(&"Interact", fields, CHAOS_SEQ))
			interact.append_array(_random_bytes(rng, rng.randi_range(1, 4)))
			packet.bytes = NetFrame.encode(schema.kind_of(&"Interact"), interact)
			packet.expect = NetRejects.Reason.PAYLOAD_TOO_LARGE
	return packet


static func _bad_payload(
	shape: Shape, rng: RandomNumberGenerator, schema: WireSchema, own: int
) -> Packet:
	var packet: Packet
	var at := NetFrame.HEADER_BYTES
	var bytes := PackedByteArray()
	match shape:
		Shape.BAD_BOOL:
			packet = message(schema, &"SetReady", {"ready": true}, CHAOS_SEQ)
			bytes = packet.bytes.duplicate()
			bytes[at + 4] = rng.randi_range(2, 255)
		Shape.BAD_ITEM:
			packet = message(schema, &"PickUp", {"item": 1}, CHAOS_SEQ)
			bytes = packet.bytes.duplicate()
			bytes.encode_u16(at + 4, 0xFFFF)
		Shape.INTERACT_TRUNCATED:
			# Interact's seq and 0 to 3 of its 4 field bytes (station, item; each may be none
			# since #770, so no value of them is bad): NetFrame takes the frame, the codec cannot
			# read it.
			var whole := schema.encode(
				WireMessage.new(&"Interact", _interact_fields(rng), CHAOS_SEQ)
			)
			var short := whole.slice(0, 4 + rng.randi_range(0, 3))
			packet = framed(schema.kind_of(&"Interact"), short, NetKindTable.Lane.RELIABLE)
		Shape.BAD_PEER:
			packet = message(schema, &"Raise", {"target": maxi(own, 2)}, CHAOS_SEQ)
			bytes = packet.bytes.duplicate()
			var target := 0 if rng.randi_range(0, 1) == 0 else 0x80000000 + rng.randi_range(0, 99)
			bytes.encode_u32(at + 4, target)
		Shape.NAN_CLAIM, Shape.INF_CLAIM:
			packet = claim(Claim.TELEPORT, schema, 0, 0, Vector3.ZERO, 0)
			bytes = packet.bytes.duplicate()
			var value := NAN if shape == Shape.NAN_CLAIM else INF * (1 - 2 * rng.randi_range(0, 1))
			bytes.encode_float(
				at + CLAIM_FLOATS_AT + 4 * rng.randi_range(0, CLAIM_FLOATS - 1), value
			)
		Shape.FLAG_BITS:
			packet = claim(Claim.TELEPORT, schema, 0, 0, Vector3.ZERO, 0)
			bytes = packet.bytes.duplicate()
			# The claim's five flags (sneaking, #990, is bit 4) leave bits 5 to 7 unknown.
			bytes[at + CLAIM_FLAGS_AT] = bytes[at + CLAIM_FLAGS_AT] | (32 << rng.randi_range(0, 2))
		Shape.BAD_ID:
			packet = message(schema, &"ChangeSettings", {"settings": {"packages": 2}}, CHAOS_SEQ)
			bytes = packet.bytes.duplicate()
			# seq, the map's count, the id's length, then its first letter: now a capital.
			bytes[at + 6] = "P".unicode_at(0)
		Shape.CODEC_TRAILING:
			var fields := {"settings": {"packages": 2}}
			var payload := schema.encode(WireMessage.new(&"ChangeSettings", fields, CHAOS_SEQ))
			payload.append(rng.randi_range(0, 255))
			packet = framed(schema.kind_of(&"ChangeSettings"), payload, NetKindTable.Lane.RELIABLE)
		Shape.EMPTY_OPUS:
			var seq_only := PackedByteArray([rng.randi_range(0, 255), rng.randi_range(0, 255)])
			packet = framed(schema.kind_of(&"VoiceUp"), seq_only, NetKindTable.Lane.VOICE)
		Shape.DEBUG_CLOCK:
			# A well-formed ForceClock from a peer other than 1, naming itself (E17): taken, it
			# would end the round in a second, and the ends would differ from the baseline's.
			var clock := {"seconds": 1}
			packet = message(schema, &"ForceClock", clock, CHAOS_SEQ, maxi(own, 2))
		Shape.NEXT_STAGE_NO_SEQ:
			# NextStage without its whole seq: NetFrame takes the frame, the codec cannot read it.
			var short := _random_bytes(rng, rng.randi_range(0, 3))
			packet = framed(schema.kind_of(&"NextStage"), short, NetKindTable.Lane.RELIABLE)
		Shape.SET_PROFILE_NO_COLOUR, Shape.SET_PROFILE_TRAILING, Shape.SET_PROFILE_BAD_NAME:
			packet = _bad_profile(shape, rng, schema)
		_:
			# DEBUG_KIND: a well-formed ForceRole from a peer other than 1 (E17).
			var role := {"role": "dissident"}
			packet = message(schema, &"ForceRole", role, CHAOS_SEQ, maxi(own, 2))
	if not bytes.is_empty():
		packet.bytes = bytes
	packet.intent = &""
	packet.seq = -1
	packet.expect = NetRejects.Reason.BAD_PAYLOAD
	return packet


static func _unassigned(rng: RandomNumberGenerator) -> int:
	return UNASSIGNED[rng.randi_range(0, UNASSIGNED.size() - 1)]


static func _random_bytes(rng: RandomNumberGenerator, count: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(count)
	for i in count:
		bytes[i] = rng.randi_range(0, 255)
	return bytes


## Interact's fields (#770): a station, an item, both or neither (-1 is none), each id 0 to 9.
static func _interact_fields(rng: RandomNumberGenerator) -> Dictionary:
	var named := rng.randi_range(0, 3)
	var station := rng.randi_range(0, 9) if named & 1 else -1
	var item := rng.randi_range(0, 9) if named & 2 else -1
	return {"station": station, "item": item}


## A SetProfile the codec refuses (#551), under its cap so NetFrame takes it: without its colour
## byte, with bytes after it, or with a name that is not UTF-8 (a lone continuation byte).
static func _bad_profile(shape: Shape, rng: RandomNumberGenerator, schema: WireSchema) -> Packet:
	var fields := {"name": "Hostile", "colour": rng.randi_range(0, 9)}
	var payload := schema.encode(WireMessage.new(&"SetProfile", fields, CHAOS_SEQ))
	match shape:
		Shape.SET_PROFILE_NO_COLOUR:
			payload = payload.slice(0, payload.size() - 1)
		Shape.SET_PROFILE_TRAILING:
			payload.append_array(_random_bytes(rng, rng.randi_range(1, 4)))
		_:
			# seq 4 bytes, the name's length byte, then its first byte.
			payload[5] = 0x80 + rng.randi_range(0, 0x3F)
	return framed(schema.kind_of(&"SetProfile"), payload, NetKindTable.Lane.RELIABLE)
