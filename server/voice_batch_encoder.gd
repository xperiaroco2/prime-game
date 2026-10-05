class_name VoiceBatchEncoder
extends RefCounted
## Builds each listener's VoiceBatch payloads of one poll (ARCHITECTURE §4.5 "Voice relay", the M5
## ADR §4's batched row, M5-4b, #374): a relayed frame's record (speaker, seq, length, Opus bytes)
## is encoded once through WireSchema, appended to each listener's batch with that listener's own
## stream's seq written in place, and a listener's records go out behind the tick and a count, as
## many per payload as the row's cap and its most frames allow; a record that does not fit starts
## the next payload. Every payload is byte for byte what WireSchema.encode gives for the
## VoiceBatch of its frames.
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
## The last header encoded, and its tick: one encoding per poll, not per listener or frame (each
## WireSchema.encode costs tens of microseconds, M5-4).
var _header_tick := -1
var _header_bytes := PackedByteArray()


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
	var one := _schema.encode(_batch(0, [_frame(down.fields, down.fields["seq"] as int)]))
	if one.is_empty():
		return one
	return one.slice(count_at + 1)


## A copy of `encoded` (record(down)) with `seq` in place of the frame's seq: byte for byte the
## record WireSchema writes for it with that seq. `seq` is a u16 (VoiceRelay renumbers modulo 2^16).
func with_seq(encoded: PackedByteArray, down: WireMessage, seq: int) -> PackedByteArray:
	if seq_offset < 0:
		var one := _schema.encode(_batch(0, [_frame(down.fields, seq)]))
		if one.is_empty():
			return one
		return one.slice(count_at + 1)
	var copy := encoded.duplicate()
	copy.encode_u16(seq_offset, seq)
	return copy


## The payloads that carry `records` (each from record() or with_seq(), in this order) under
## `tick`: as few as the cap and the most frames allow, each filled in order. Empty for no records,
## or when the codec refused the tick (it logged why).
func payloads(tick: int, records: Array[PackedByteArray]) -> Array[PackedByteArray]:
	var batches := start(tick)
	for each: PackedByteArray in records:
		batches.add(each)
	return batches.finish()


## One listener's batches under `tick`, filled frame by frame (Batches.add_frame).
func start(tick: int) -> Batches:
	return Batches.new(self, _header(tick))


## One listener's VoiceBatches of one poll, filled in order as its frames come: a record that would
## pass the cap or the most frames closes the payload and starts the next. With the seq patched in
## place, a frame costs one append and one u16 write, no copy of its record.
class Batches:
	extends RefCounted
	var _encoder: VoiceBatchEncoder
	var _header: PackedByteArray
	var _found: Array[PackedByteArray] = []
	var _payload := PackedByteArray()
	var _count := 0

	func _init(encoder: VoiceBatchEncoder, header: PackedByteArray) -> void:
		_encoder = encoder
		_header = header

	## `encoded` (VoiceBatchEncoder.record(down)) with the listener's own `seq`.
	func add_frame(encoded: PackedByteArray, down: WireMessage, seq: int) -> void:
		if _encoder.seq_offset < 0:
			var whole := _encoder.with_seq(encoded, down, seq)
			if not whole.is_empty():
				add(whole)
			return
		var at := add(encoded)
		if at >= 0:
			_payload.encode_u16(at + _encoder.seq_offset, seq)

	## Appends a record as it is; where it starts in the current payload, -1 when the header was
	## refused (nothing is sent then).
	func add(record: PackedByteArray) -> int:
		if _header.is_empty():
			return -1
		var full := _count == _encoder.max_frames
		if _count > 0 and (full or _payload.size() + record.size() > _encoder.cap):
			_close()
		if _count == 0:
			_payload = _header.duplicate()
		var at := _payload.size()
		_payload.append_array(record)
		_count += 1
		return at

	## Every payload, the last one closed.
	func finish() -> Array[PackedByteArray]:
		if _count > 0:
			_close()
		return _found

	func _close() -> void:
		_payload[_encoder.count_at] = _count
		_found.append(_payload)
		_count = 0


## What WireSchema writes for a batch of no frames under `tick`: the bytes before the first record.
func _header(tick: int) -> PackedByteArray:
	if tick != _header_tick:
		_header_bytes = _schema.encode(_batch(tick, []))
		_header_tick = tick if not _header_bytes.is_empty() else -1
	return _header_bytes


static func _batch(tick: int, frames: Array[Dictionary]) -> WireMessage:
	return WireMessage.new(VOICE_BATCH, {"tick": tick, FRAMES: frames})


static func _frame(fields: Dictionary, seq: int) -> Dictionary:
	return {"speaker": fields["speaker"], SEQ: seq, "opus": fields["opus"]}
