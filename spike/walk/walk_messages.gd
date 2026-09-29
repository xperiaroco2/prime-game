class_name SpikeWalkMessages
extends RefCounted
## Spike (#14): the walk spike's message schemas and their defensive decoding. A message is an
## Array [kind, fields...] in var_to_bytes format; bytes_to_var never decodes objects, and bytes
## after a valid message make it invalid.
##   client -> host: [MOVE, epoch: int, pos: Vector3, yaw: float]
##       Client-side movement (ARCHITECTURE §7): a claim the host checks, never trusted state.
##   host -> one client: [PLACE, epoch: int, pos: Vector3]
##       The spawn point, or a correction after a rejected move. Starts a new epoch.
##   host -> all: [SNAPSHOT, tick: int, ids: PackedInt32Array, pos: PackedVector3Array,
##       yaws: PackedFloat32Array]

const KIND_MOVE := 1
const KIND_PLACE := 2
const KIND_SNAPSHOT := 3
const MAX_BYTES := 1024
const MAX_PLAYERS := 16


static func encode_move(epoch: int, pos: Vector3, yaw: float) -> PackedByteArray:
	return var_to_bytes([KIND_MOVE, epoch, pos, yaw])


static func encode_place(epoch: int, pos: Vector3) -> PackedByteArray:
	return var_to_bytes([KIND_PLACE, epoch, pos])


static func encode_snapshot(
	tick: int, ids: PackedInt32Array, positions: PackedVector3Array, yaws: PackedFloat32Array
) -> PackedByteArray:
	return var_to_bytes([KIND_SNAPSHOT, tick, ids, positions, yaws])


## The message as [kind, fields...], or [] when the bytes are not exactly one valid message.
static func decode(bytes: PackedByteArray) -> Array:
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return []
	var value: Variant = bytes_to_var(bytes)
	if typeof(value) != TYPE_ARRAY:
		return []
	var msg: Array = value
	if not (_is_move(msg) or _is_place(msg) or _is_snapshot(msg)):
		return []
	# Trailing bytes: a valid message re-encodes to exactly the bytes it came from.
	if var_to_bytes(msg).size() != bytes.size():
		return []
	return msg


static func _kind_is(msg: Array, kind: int, size: int) -> bool:
	return msg.size() == size and typeof(msg[0]) == TYPE_INT and msg[0] == kind


static func _is_move(msg: Array) -> bool:
	return (
		_kind_is(msg, KIND_MOVE, 4)
		and typeof(msg[1]) == TYPE_INT
		and typeof(msg[2]) == TYPE_VECTOR3
		and (msg[2] as Vector3).is_finite()
		and typeof(msg[3]) == TYPE_FLOAT
		and is_finite(msg[3] as float)
	)


static func _is_place(msg: Array) -> bool:
	return (
		_kind_is(msg, KIND_PLACE, 3)
		and typeof(msg[1]) == TYPE_INT
		and typeof(msg[2]) == TYPE_VECTOR3
		and (msg[2] as Vector3).is_finite()
	)


static func _is_snapshot(msg: Array) -> bool:
	if (
		not _kind_is(msg, KIND_SNAPSHOT, 5)
		or typeof(msg[1]) != TYPE_INT
		or typeof(msg[2]) != TYPE_PACKED_INT32_ARRAY
		or typeof(msg[3]) != TYPE_PACKED_VECTOR3_ARRAY
		or typeof(msg[4]) != TYPE_PACKED_FLOAT32_ARRAY
	):
		return false
	var ids: PackedInt32Array = msg[2]
	var positions: PackedVector3Array = msg[3]
	var yaws: PackedFloat32Array = msg[4]
	if ids.size() > MAX_PLAYERS or positions.size() != ids.size() or yaws.size() != ids.size():
		return false
	for p in positions:
		if not p.is_finite():
			return false
	for y in yaws:
		if not is_finite(y):
			return false
	return true
