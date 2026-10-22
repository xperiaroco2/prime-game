class_name WireText
extends RefCounted
## WireField's text checks (ARCHITECTURE §4.3): what an id, a path, printable text and a `name`
## may hold, and the hand-made UTF-8 check a `name` passes before any decode (#550). WireField's
## is_id, is_path, is_printable, is_name and is_name_char call these; the bounds are WireField's.

## Per UTF-8 continuation count: the lead byte's bits of the code point, and the smallest code
## point that needs that many bytes (anything smaller is an overlong form).
const UTF8_LEAD_BITS := [0x7F, 0x1F, 0x0F, 0x07]
const UTF8_SMALLEST := [0, 0x80, 0x800, 0x10000]


## Whether `text` is a wire id: 1 to 32 bytes of `a-z`, `0-9` and `_`.
static func is_id(text: String) -> bool:
	if text.length() < 1 or text.length() > WireField.ID_MAX:
		return false
	for i: int in text.length():
		if not is_id_char(text.unicode_at(i)):
			return false
	return true


## Whether `text` is a wire path: `res://` and bytes of `A-Z a-z 0-9 _ - . /`, no `..`, at most
## 255 bytes.
static func is_path(text: String) -> bool:
	var prefix := WireField.PATH_PREFIX
	if text.length() > WireField.PATH_MAX or not text.begins_with(prefix) or text.contains(".."):
		return false
	for i: int in range(prefix.length(), text.length()):
		if not is_path_char(text.unicode_at(i)):
			return false
	return true


## Whether `text` is printable ASCII (0x20 to 0x7E) of at most `most` bytes.
static func is_printable(text: String, most: int) -> bool:
	if text.length() > most:
		return false
	for i: int in text.length():
		if not is_printable_char(text.unicode_at(i)):
			return false
	return true


## Whether `text` is a `name` on the wire (#550): at most NAME_MAX_BYTES bytes of UTF-8, every
## character one is_name_char allows. Empty is one (the host gives a fallback).
static func is_name(text: String) -> bool:
	for i: int in text.length():
		if not is_name_char(text.unicode_at(i)):
			return false
	return text.to_utf8_buffer().size() <= WireField.NAME_MAX_BYTES


## Whether a `name` may hold the character `code`: not a C0 control, DEL or a C1 control, not a
## surrogate, not U+FEFF (a UTF-8 decoder may drop it silently, so it would not decode back to the
## same bytes), not an invisible format character (U+200B to U+200F, U+2028 to U+202E, U+2060 to
## U+2064, U+2066 to U+2069: a name that looks like another) and at most U+10FFFF. core/'s
## PlayerNames.is_dropped refuses exactly these (net/ names no core/ class; a test pins the two), so
## every name the host makes encodes.
static func is_name_char(code: int) -> bool:
	return not (
		code < 0x20
		or (code >= 0x7F and code <= 0x9F)
		or (code >= 0x200B and code <= 0x200F)
		or (code >= 0x2028 and code <= 0x202E)
		or (code >= 0x2060 and code <= 0x2064)
		or (code >= 0x2066 and code <= 0x2069)
		or (code >= 0xD800 and code <= 0xDFFF)
		or code == 0xFEFF
		or code > 0x10FFFF
	)


static func is_id_char(c: int) -> bool:
	return (c >= 0x61 and c <= 0x7A) or (c >= 0x30 and c <= 0x39) or c == 0x5F


static func is_path_char(c: int) -> bool:
	# A-Z, then "-", "." and "/".
	return is_id_char(c) or (c >= 0x41 and c <= 0x5A) or c in [0x2D, 0x2E, 0x2F]


static func is_printable_char(c: int) -> bool:
	return c >= 0x20 and c <= 0x7E


## Where `raw` stops being well-formed UTF-8 (RFC 3629: the shortest form only, no surrogate,
## nothing above U+10FFFF), or -1 when it is; a character is_name_char refuses is a problem too.
static func utf8_problem(raw: PackedByteArray) -> int:
	var at := 0
	while at < raw.size():
		var tail := utf8_tail(raw[at])
		if tail < 0 or at + tail >= raw.size():
			return at
		var code: int = raw[at] & UTF8_LEAD_BITS[tail]
		for i: int in range(1, tail + 1):
			var byte := raw[at + i]
			if byte & 0xC0 != 0x80:
				return at
			code = (code << 6) | (byte & 0x3F)
		if code < UTF8_SMALLEST[tail] or not is_name_char(code):
			return at
		at += tail + 1
	return -1


## How many continuation bytes follow the lead byte `lead`; -1 when it cannot lead (a continuation
## byte, C0 and C1, which only lead overlong forms, and F5 to FF, which lead nothing below
## U+110000).
static func utf8_tail(lead: int) -> int:
	if lead < 0x80:
		return 0
	if lead >= 0xC2 and lead <= 0xDF:
		return 1
	if lead >= 0xE0 and lead <= 0xEF:
		return 2
	if lead >= 0xF0 and lead <= 0xF4:
		return 3
	return -1
