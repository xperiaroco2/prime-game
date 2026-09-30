class_name WireReader
extends RefCounted
## A bounds-checked reader over one payload (ARCHITECTURE §4.4). Every read checks that enough
## bytes are left before it calls `decode_*`, which "fails" (the 4.7.2 docs) when too few are
## left: reading first could print engine errors that one peer can repeat at will. The first
## problem fails the whole message: every later read returns a zero value and changes nothing.

var failed := false
## Why the message failed, for tests and logs; empty while it has not.
var problem := ""

var _bytes: PackedByteArray
var _at := 0


func _init(payload: PackedByteArray) -> void:
	_bytes = payload


## Bytes not read yet.
func left() -> int:
	return _bytes.size() - _at


func at_end() -> bool:
	return _at == _bytes.size()


## Fails the message; the first reason is kept.
func fail(reason: String) -> void:
	if not failed:
		failed = true
		problem = reason


func u8() -> int:
	if not _has(1):
		return 0
	var value := _bytes.decode_u8(_at)
	_at += 1
	return value


func u16() -> int:
	if not _has(2):
		return 0
	var value := _bytes.decode_u16(_at)
	_at += 2
	return value


func u32() -> int:
	if not _has(4):
		return 0
	var value := _bytes.decode_u32(_at)
	_at += 4
	return value


func s32() -> int:
	if not _has(4):
		return 0
	var value := _bytes.decode_s32(_at)
	_at += 4
	return value


func s64() -> int:
	if not _has(8):
		return 0
	var value := _bytes.decode_s64(_at)
	_at += 8
	return value


## An IEEE 754 single; NaN and the infinities fail the message.
func f32() -> float:
	if not _has(4):
		return 0.0
	var value := _bytes.decode_float(_at)
	_at += 4
	if not is_finite(value):
		fail("a float that is not finite")
		return 0.0
	return value


## `count` raw bytes; a negative count fails the message.
func raw(count: int) -> PackedByteArray:
	if count < 0:
		fail("a negative length")
		return PackedByteArray()
	if not _has(count):
		return PackedByteArray()
	var value := _bytes.slice(_at, _at + count)
	_at += count
	return value


## Every byte not read yet (an Opus frame, which is the rest of its payload).
func rest() -> PackedByteArray:
	return raw(left())


func _has(count: int) -> bool:
	if failed:
		return false
	if left() < count:
		fail("truncated")
		return false
	return true
