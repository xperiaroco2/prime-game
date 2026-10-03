class_name VoiceDownEncoder
extends RefCounted
## Encodes a relayed frame's VoiceDown once and gives each listener a copy with its own stream's
## seq written in (ARCHITECTURE §4.5 "Voice relay", #245): only the u16 seq differs between one
## frame's listeners, and encoding through WireSchema was most of the relay's time (M5-4, §6 "The
## wire"). Every copy is byte for byte what WireSchema.encode gives for the VoiceDown with that seq.
##
## The seq's offset comes from the schema's row (WireRow.fixed_offset), never a byte index written
## here: a row change that moves the seq behind a field of varying size, or widens it, leaves
## `seq_offset` at -1 and every copy encoded in full (slower, never corrupt), and
## voice_down_encoder_test fails on the lost fast path.

## The field the copies differ in.
const SEQ := "seq"

## VoiceDown's kind.
var kind := 0
## The seq's byte offset in every VoiceDown payload; -1 when it cannot be patched in place.
var seq_offset := -1

var _schema: WireSchema


func _init(schema: WireSchema) -> void:
	_schema = schema
	var row := schema.row_named(VoiceRelay.VOICE_DOWN)
	kind = row.kind
	var seq := row.field_named(SEQ)
	if seq != null and seq.type == WireField.Type.U16:
		seq_offset = row.fixed_offset(SEQ)


## The payload of `message` (a VoiceDown), as WireSchema.encode gives it; empty when the codec
## refused it (it logged why).
func encode(message: WireMessage) -> PackedByteArray:
	return _schema.encode(message)


## A copy of `encoded` (encode(message)) with `seq` in place of the message's seq: byte for byte
## WireSchema.encode of `message` with that seq. `seq` is a u16 (VoiceRelay renumbers modulo 2^16).
func with_seq(encoded: PackedByteArray, message: WireMessage, seq: int) -> PackedByteArray:
	if seq_offset < 0:
		var fields := message.fields.duplicate()
		fields[SEQ] = seq
		return _schema.encode(WireMessage.new(message.name, fields))
	var copy := encoded.duplicate()
	copy.encode_u16(seq_offset, seq)
	return copy
