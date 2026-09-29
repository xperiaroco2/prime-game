class_name SpikeNetMessages
extends RefCounted
## Spike (#13): the two message schemas and their defensive decoding. A message is an Array
## [kind, fields...] in var_to_bytes format; bytes_to_var never decodes objects.
##   client -> host: [KIND_MOVE_INTENT, dir: Vector2]  (a direction, never a position)
##   host -> all:    [KIND_POSITIONS, ids: PackedInt32Array, positions: PackedVector2Array]

const KIND_MOVE_INTENT := 1
const KIND_POSITIONS := 2
const MAX_BYTES := 1024
const MAX_PLAYERS := 16


static func encode_move_intent(dir: Vector2) -> PackedByteArray:
	return var_to_bytes([KIND_MOVE_INTENT, dir])


static func encode_positions(
	ids: PackedInt32Array, positions: PackedVector2Array
) -> PackedByteArray:
	return var_to_bytes([KIND_POSITIONS, ids, positions])


## The message as [kind, fields...], or [] when the bytes are not a valid message of any kind.
static func decode(bytes: PackedByteArray) -> Array:
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return []
	var value: Variant = bytes_to_var(bytes)
	if typeof(value) != TYPE_ARRAY:
		return []
	var msg: Array = value
	if _is_move_intent(msg) or _is_positions(msg):
		return msg
	return []


static func _is_move_intent(msg: Array) -> bool:
	return (
		msg.size() == 2
		and typeof(msg[0]) == TYPE_INT
		and msg[0] == KIND_MOVE_INTENT
		and typeof(msg[1]) == TYPE_VECTOR2
		and (msg[1] as Vector2).is_finite()
	)


static func _is_positions(msg: Array) -> bool:
	if (
		msg.size() != 3
		or typeof(msg[0]) != TYPE_INT
		or msg[0] != KIND_POSITIONS
		or typeof(msg[1]) != TYPE_PACKED_INT32_ARRAY
		or typeof(msg[2]) != TYPE_PACKED_VECTOR2_ARRAY
	):
		return false
	var ids: PackedInt32Array = msg[1]
	var positions: PackedVector2Array = msg[2]
	if ids.size() != positions.size() or ids.size() > MAX_PLAYERS:
		return false
	for p in positions:
		if not p.is_finite():
			return false
	return true
