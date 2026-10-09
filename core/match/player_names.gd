class_name PlayerNames
extends RefCounted
## The rules of a player's own name (ARCHITECTURE §3.5, #550; the engineer's answers on #73): at
## most MAX_CHARS characters, never empty (the host falls back to Player<n>), and a name another
## present player has gets a suffix ("Dima", then "Dima 2"), decided by the host. Pure: the host's
## JoinRules uses it on every Hello, the client's settings store on every name it keeps, so what a
## client sends always fits the wire's `name` type (net/'s WireField.is_name_char mirrors
## is_dropped; a test pins the two).

## The most characters (Unicode code points) a name keeps: the engineer's answer on #73. At most 4
## UTF-8 bytes each, so a name is at most 64 bytes on the wire.
const MAX_CHARS := 16


## `raw` as a name: the characters is_dropped names removed, the blank edges (is_blank) trimmed,
## then cut to MAX_CHARS characters and trimmed again. Anything but a String or StringName is "";
## "" means no usable name (the host's fallback).
static func clean(raw: Variant) -> String:
	if not (raw is String or raw is StringName):
		return ""
	var kept := PackedInt32Array()
	for code: int in _codes(str(raw)):
		if not is_dropped(code):
			kept.append(code)
	var trimmed := _trimmed(kept)
	if trimmed.size() > MAX_CHARS:
		trimmed = _trimmed(trimmed.slice(0, MAX_CHARS))
	return _as_string(trimmed)


## `wanted` (a clean() name), or when a name in `taken` equals it ignoring case, the first of
## "<wanted> 2", "<wanted> 3" and so on that none equals, `wanted` cut so the whole stays within
## MAX_CHARS characters.
static func unique(wanted: String, taken: PackedStringArray) -> String:
	var lowered := {}
	for each: String in taken:
		lowered[each.to_lower()] = true
	if not lowered.has(wanted.to_lower()):
		return wanted
	# Each name in `taken` blocks at most one number, so one of these is free.
	for number: int in range(2, taken.size() + 3):
		var suffix := " %d" % number
		var base := wanted.left(MAX_CHARS - suffix.length())
		var candidate := _as_string(_trimmed(_codes(base))) + suffix
		if not lowered.has(candidate.to_lower()):
			return candidate
	return wanted


## Whether a name drops the character `code`: the C0 controls, DEL and the C1 controls, a
## surrogate (never a character of its own), U+FEFF (the byte-order mark, which a UTF-8 decoder
## may drop silently), anything above U+10FFFF, and the invisible format characters (zero-width
## marks, the line and paragraph separators, the bidi controls, the invisible operators: U+200B to
## U+200F, U+2028 to U+202E, U+2060 to U+2064, U+2066 to U+2069), which would let two names that
## look alike pass as different, "Di<U+200B>ma" beside "Dima". The wire's `name` type rejects the
## same.
static func is_dropped(code: int) -> bool:
	return (
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


## Whether `code` is blank at a name's edges: the space and the Unicode spaces that show nothing
## (no-break, en to hair, zero-width, the line and paragraph separators, ideographic), so a name of
## blanks alone is no name.
static func is_blank(code: int) -> bool:
	return (
		code == 0x20
		or code == 0xA0
		or code == 0x1680
		or (code >= 0x2000 and code <= 0x200B)
		or code == 0x2028
		or code == 0x2029
		or code == 0x202F
		or code == 0x205F
		or code == 0x3000
	)


static func _trimmed(codes: PackedInt32Array) -> PackedInt32Array:
	var start := 0
	var end := codes.size()
	while start < end and is_blank(codes[start]):
		start += 1
	while end > start and is_blank(codes[end - 1]):
		end -= 1
	return codes.slice(start, end)


static func _codes(text: String) -> PackedInt32Array:
	var codes := PackedInt32Array()
	for i: int in text.length():
		codes.append(text.unicode_at(i))
	return codes


static func _as_string(codes: PackedInt32Array) -> String:
	var found := ""
	for code: int in codes:
		found += String.chr(code)
	return found
