class_name SpikeVoiceMessages
extends RefCounted
## Spike (#15): the proximity voice messages and their defensive decoding, in the format of
## SpikeWalkMessages: an Array [kind, fields...] in var_to_bytes format, exactly one message per
## packet. The kinds do not overlap the walk kinds, so one packet decodes as at most one of them.
##   client -> host: [VOICE_UP, seq: int, opus: PackedByteArray]
##       20 ms of the speaker's voice. The host decides who hears it (SpikeVoiceRouting).
##   host -> one listener: [VOICE_DOWN, speaker: int, seq: int, opus: PackedByteArray]
##       The same frame, relayed only to listeners the host's routing rule entitles to it.

const KIND_VOICE_UP := 11
const KIND_VOICE_DOWN := 12
## An Opus frame of 20 ms at 24 kbit/s is about 60 bytes; 400 leaves room for loud, noisy speech
## and still keeps one frame far below the MTU.
const MAX_OPUS_BYTES := 400
const MAX_BYTES := 512


static func encode_up(seq: int, opus: PackedByteArray) -> PackedByteArray:
	return var_to_bytes([KIND_VOICE_UP, seq, opus])


static func encode_down(speaker: int, seq: int, opus: PackedByteArray) -> PackedByteArray:
	return var_to_bytes([KIND_VOICE_DOWN, speaker, seq, opus])


## The message as [kind, fields...], or [] when the bytes are not exactly one valid voice message.
static func decode(bytes: PackedByteArray) -> Array:
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return []
	var value: Variant = bytes_to_var(bytes)
	if typeof(value) != TYPE_ARRAY:
		return []
	var msg: Array = value
	if not (_is_up(msg) or _is_down(msg)):
		return []
	# Trailing bytes: a valid message re-encodes to exactly the bytes it came from.
	if var_to_bytes(msg).size() != bytes.size():
		return []
	return msg


static func _kind_is(msg: Array, kind: int, size: int) -> bool:
	return msg.size() == size and typeof(msg[0]) == TYPE_INT and msg[0] == kind


static func _is_opus(value: Variant) -> bool:
	if typeof(value) != TYPE_PACKED_BYTE_ARRAY:
		return false
	var opus: PackedByteArray = value
	return not opus.is_empty() and opus.size() <= MAX_OPUS_BYTES


static func _is_up(msg: Array) -> bool:
	return (
		_kind_is(msg, KIND_VOICE_UP, 3)
		and typeof(msg[1]) == TYPE_INT
		and (msg[1] as int) >= 0
		and _is_opus(msg[2])
	)


static func _is_down(msg: Array) -> bool:
	return (
		_kind_is(msg, KIND_VOICE_DOWN, 4)
		and typeof(msg[1]) == TYPE_INT
		and typeof(msg[2]) == TYPE_INT
		and (msg[2] as int) >= 0
		and _is_opus(msg[3])
	)
