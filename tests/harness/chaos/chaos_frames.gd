class_name ChaosFrames
extends RefCounted
## What a modified client can put on the wire, each input built so that the host's answer is known
## from ARCHITECTURE alone (§4 Transport, §4.3 the wire types, §4.4 the codec, §4.5 the session):
## - malformed frames (Shape): NetFrame's rejects (too short, too large, an unknown kind, random
##   bytes behind one, the wrong direction or lane, a payload over its kind's cap, truncated,
##   trailing bytes) and the codec's (a bool that is not 0 or 1, an item 0xFFFF, a peer 0, a NaN or
##   infinite float, unknown flag bits, an id with a capital letter, bytes after the last field, an
##   empty Opus frame), and the debug kinds (ForceRole, kind 24; ForceClock, kind 25, one second)
##   from a peer other than 1, which the host counts as bad payloads (E17). Each Packet names the
##   NetRejects reason it must be counted under (`expect`);
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
}

## The hostile MoveClaims. STALE_TICK repeats a client tick the host already has: dropped, or, as
## the first claim of a new baseline, checked as one tick and corrected (§7.1; both allowed).
## NEAR_ITEM claims the position it is given (an item resting far away, ahead of a PickUp of it):
## not one of the random shapes (RANDOM_CLAIMS), its caller picks the item.
enum Claim { TELEPORT, SPEED, FUTURE_TICK, JUMPS, OTHER_EPOCH, STALE_TICK, NEAR_ITEM }

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
## How far past its last claim a "future" client tick goes: past MAX_TICK_CREDIT (200 ticks).
const FUTURE_TICKS := 5000
## Kinds no row of the table has (0 is the transport's ADMIT, never a client's).
## The Claim shapes a chaos peer draws at random: the ones before NEAR_ITEM.
const RANDOM_CLAIMS := Claim.NEAR_ITEM
const UNASSIGNED: Array[int] = [0, 14, 19, 23, 26, 31, 66, 80, 95, 97, 111, 114, 127, 128, 200, 255]
## MoveClaim's layout (§4.3): the first float of position, velocity and facing, and the flags.
const CLAIM_FLOATS_AT := 8
const CLAIM_FLOATS := 9
const CLAIM_FLAGS_AT := 44


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
	if shape <= Shape.TRAILING:
		packet = _bad_frame(shape, rng, schema)
	else:
		packet = _bad_payload(shape, rng, schema, own)
	packet.label = "malformed %s" % Shape.find_key(shape)
	return packet


## A hostile MoveClaim of `shape` from a player standing at `at` in `epoch`, whose last claim
## carried `last_tick`; `index` makes its tag unique. NEAR_ITEM claims `at` itself, which its
## caller sets to a point far from where the player stands.
static func claim(
	shape: Claim, schema: WireSchema, epoch: int, last_tick: int, at: Vector3, index: int
) -> Packet:
	var position := at + Vector3(TELEPORT_M, 0.0, 0.0)
	var tick := last_tick + 1
	var claimed_epoch := epoch
	var jumps := 0
	match shape:
		Claim.SPEED:
			position = at + Vector3(0.0, 0.0, SPEED_M)
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
		"facing": Vector3.FORWARD,
		"sprint": false,
		"moving": true,
		"on_floor": true,
		"jumps": jumps,
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
			var rejected := {"seq": CHAOS_SEQ, "reason": &"not_accepted"}
			var payload := schema.encode(WireMessage.new(&"Rejected", rejected))
			packet.bytes = NetFrame.encode(schema.kind_of(&"Rejected"), payload)
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
			bytes[at + CLAIM_FLAGS_AT] = bytes[at + CLAIM_FLAGS_AT] | (8 << rng.randi_range(0, 4))
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
