class_name VoiceBatchEncoder
extends RefCounted
## Builds each listener's VoiceBatch payloads of one poll (ARCHITECTURE §4.5 "Voice relay", the M5
## ADR §4's batched row, M5-4b, #374): a relayed frame's record (speaker, seq, length, Opus bytes)
## is encoded once through WireSchema, each listener's copy gets its own stream's seq written in,
## and a listener's records go out behind the tick and a count, as many per payload as the row's
## cap and its most frames allow; a record that does not fit starts the next payload. Every
## payload is byte for byte what WireSchema.encode gives for the VoiceBatch of its frames.
##
## The seq's offset in a record comes from the schema (WireField.fixed_offset), never a byte index
## written here: a row change that moves the seq behind a part of varying size, or widens it,
## leaves `seq_offset` at -1 and every copy encoded in full (slower, never corrupt), and
## voice_batch_encoder_test fails on the lost fast path. The header is what WireSchema writes for
## a batch of no frames, its last byte the list's u8 count (§4.3's list).

const VOICE_BATCH := &"VoiceBatch"
const FRAMES := "frames"
const SEQ := "seq"

## VoiceBatch's kind.
var kind := 0
## The most bytes of one payload (the row's cap) and the most frames in one.
var cap := 0
var max_frames := 0
## The seq's byte offset in every frame's record; -1 when it cannot be patched in place.
var seq_offset := -1
## Where every payload holds its count of frames (the header's last byte).
var count_at := 0

var _schema: WireSchema


func _init(schema: WireSchema) -> void:
	_schema = schema
	var row := schema.row_named(VOICE_BATCH)
	kind = row.kind
	cap = row.cap
	var frames := row.field_named(FRAMES)
	max_frames = frames.max_count
	for part: WireField in frames.element.parts:
		if part.name == SEQ and part.type == WireField.Type.U16:
			seq_offset = frames.element.fixed_offset(SEQ)
	count_at = _header(0).size() - 1


## The record of one relayed frame (`down`: a VoiceDown's speaker, seq and opus), as WireSchema
## writes it inside a VoiceBatch; empty when the codec refused it (it logged why).
func record(down: WireMessage) -> PackedByteArray:
	var header := _header(0)
	var one := _schema.encode(_batch(0, [_frame(down.fields, down.fields["seq"] as int)]))
	if header.is_empty() or one.is_empty():
		return PackedByteArray()
	return one.slice(header.size())


## A copy of `encoded` (record(down)) with `seq` in place of the frame's seq: byte for byte the
## record WireSchema writes for it with that seq. `seq` is a u16 (VoiceRelay renumbers modulo 2^16).
func with_seq(encoded: PackedByteArray, down: WireMessage, seq: int) -> PackedByteArray:
	if seq_offset < 0:
		var header := _header(0)
		var one := _schema.encode(_batch(0, [_frame(down.fields, seq)]))
		if header.is_empty() or one.is_empty():
			return PackedByteArray()
		return one.slice(header.size())
	var copy := encoded.duplicate()
	copy.encode_u16(seq_offset, seq)
	return copy


## The payloads that carry `records` (each from record() or with_seq(), in this order) under
## `tick`: as few as the cap and the most frames allow, each filled in order. Empty for no records,
## or when the codec refused the tick (it logged why).
func payloads(tick: int, records: Array[PackedByteArray]) -> Array[PackedByteArray]:
	var found: Array[PackedByteArray] = []
	var header := _header(tick)
	if header.is_empty():
		return found
	var payload := PackedByteArray()
	var count := 0
	for each: PackedByteArray in records:
		if count > 0 and (count == max_frames or payload.size() + each.size() > cap):
			payload[count_at] = count
			found.append(payload)
			count = 0
		if count == 0:
			payload = header.duplicate()
		payload.append_array(each)
		count += 1
	if count > 0:
		payload[count_at] = count
		found.append(payload)
	return found


## What WireSchema writes for a batch of no frames under `tick`: the bytes before the first record.
func _header(tick: int) -> PackedByteArray:
	return _schema.encode(_batch(tick, []))


static func _batch(tick: int, frames: Array[Dictionary]) -> WireMessage:
	return WireMessage.new(VOICE_BATCH, {"tick": tick, FRAMES: frames})


static func _frame(fields: Dictionary, seq: int) -> Dictionary:
	return {"speaker": fields["speaker"], SEQ: seq, "opus": fields["opus"]}
