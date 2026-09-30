class_name WireWriter
extends RefCounted
## Appends little-endian fields to one payload (ARCHITECTURE §4.4), through
## `PackedByteArray.encode_*`: never `var_to_bytes`, whose framing is as large as an Opus frame.
## The caller has checked every value against its wire type (WireField) before it writes.

var bytes := PackedByteArray()


func u8(value: int) -> void:
	bytes.append(value)


func u16(value: int) -> void:
	var at := _grow(2)
	bytes.encode_u16(at, value)


func u32(value: int) -> void:
	var at := _grow(4)
	bytes.encode_u32(at, value)


func s32(value: int) -> void:
	var at := _grow(4)
	bytes.encode_s32(at, value)


func s64(value: int) -> void:
	var at := _grow(8)
	bytes.encode_s64(at, value)


func f32(value: float) -> void:
	var at := _grow(4)
	bytes.encode_float(at, value)


func raw(value: PackedByteArray) -> void:
	bytes.append_array(value)


func _grow(count: int) -> int:
	var at := bytes.size()
	bytes.resize(at + count)
	return at
