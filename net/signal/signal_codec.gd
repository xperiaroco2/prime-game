class_name SignalCodec
extends RefCounted
## The signalling protocol's messages (ARCHITECTURE §4.8; the M6 ADR §2.4): JSON text, each with
## "t" (the type) and "v" (VERSION). decode() checks a message from one side against that side's
## types and fields and returns only the fields it knows, rebuilt, so nothing a sender adds is ever
## forwarded; encode() refuses what decode() would reject. The service (SignalRouter) and the
## client (Signaller) use the same rules, and the Worker (M6-5b) replays the same transcripts.
##
## A message is printable ASCII (tab, CR and LF allowed) of at most MAX_MESSAGE_BYTES: a non-ASCII
## byte would make get_string_from_utf8 print an engine error a peer could repeat at will.
## Integers are JSON numbers with no fraction; the content hash, an s64, travels as 16 hex digits.

## Who sent a message, which picks its allowed types and their fields.
enum Side {
	## To the service, from a socket that has no role yet: only "open" and "join".
	UNSET,
	## To the service, from a room's host.
	HOST,
	## To the service, from a joiner.
	JOINER,
	## From the service to a room's host.
	TO_HOST,
	## From the service to a joiner.
	TO_JOINER,
}

enum Field { INT, U16, ID, MAX_JOINERS, CODE, CONTENT, SDP, MID, INDEX, CAND, ICE, WHY }

const VERSION := 1
## Placeholders, "not a decision" (the ADR §2.4).
const MAX_MESSAGE_BYTES := 16384
const CODE_LENGTH := 6
## 31 characters that cannot be misread: no 0, O, 1, I or L.
const CODE_ALPHABET := "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
const MAX_ICE_SERVERS := 8
const MAX_ICE_URLS := 4
const MAX_ICE_TEXT := 512
const MAX_SDP := 12288
const MAX_CAND := 1024
const MAX_MID := 64
const MAX_WHY := 64
const MAX_JOINERS := 255

## The reasons an error carries ("why"). The client maps each to its text.
const WHY_VERSION := "update the game"
const WHY_BAD := "bad message"
const WHY_TOO_LARGE := "too large"
const WHY_NOT_ALLOWED := "not allowed"
const WHY_NO_ROOM := "no such room"
const WHY_STARTED := "the match has started"
const WHY_FULL := "the room is full"
const WHY_NO_JOINER := "no such joiner"
const WHY_CANDIDATES := "too many candidates"
const WHY_HOST_LEFT := "the host left"
const WHY_BUSY := "no free code"

## Side -> type -> field -> Field. A field marked optional in OPTIONAL may be absent.
const TYPES := {
	Side.UNSET:
	{
		"open": {"protocol": Field.U16, "content": Field.CONTENT, "max": Field.MAX_JOINERS},
		"join": {"code": Field.CODE},
	},
	Side.HOST:
	{
		"offer": {"to": Field.ID, "id": Field.ID, "sdp": Field.SDP},
		"candidate": {"to": Field.ID, "mid": Field.MID, "index": Field.INDEX, "cand": Field.CAND},
		"close": {},
		"reopen": {},
	},
	Side.JOINER:
	{
		"answer": {"sdp": Field.SDP},
		"candidate": {"mid": Field.MID, "index": Field.INDEX, "cand": Field.CAND},
	},
	Side.TO_HOST:
	{
		"room": {"code": Field.CODE, "ice_servers": Field.ICE},
		"join": {"from": Field.ID},
		"answer": {"from": Field.ID, "sdp": Field.SDP},
		"candidate": {"from": Field.ID, "mid": Field.MID, "index": Field.INDEX, "cand": Field.CAND},
		"error": {"why": Field.WHY},
	},
	Side.TO_JOINER:
	{
		"found": {"protocol": Field.U16, "content": Field.CONTENT},
		"offer": {"id": Field.ID, "sdp": Field.SDP, "ice_servers": Field.ICE},
		"candidate": {"mid": Field.MID, "index": Field.INDEX, "cand": Field.CAND},
		"error": {"why": Field.WHY},
	},
}
## Every type of the protocol: one that is not the sender's is "not allowed", any other "bad".
const KNOWN_TYPES: Array[String] = [
	"open", "room", "join", "found", "offer", "answer", "candidate", "close", "reopen", "error"
]
const MAX_ID := 2147483647


## A decoded message: its type and its checked fields, or the reason it was refused.
class Decoded:
	extends RefCounted
	var type := ""
	var fields: Dictionary[String, Variant] = {}
	## "" when the message is valid; else one of the WHY_ reasons.
	var why := ""

	func ok() -> bool:
		return why == ""


## Checks one received message from `side` (a Side). Never prints an engine error, whatever
## the bytes.
static func decode(bytes: PackedByteArray, side: int) -> Decoded:
	var result := Decoded.new()
	if bytes.size() > MAX_MESSAGE_BYTES:
		result.why = WHY_TOO_LARGE
		return result
	if not _printable(bytes):
		result.why = WHY_BAD
		return result
	var json := JSON.new()
	if json.parse(bytes.get_string_from_ascii()) != OK or not json.data is Dictionary:
		result.why = WHY_BAD
		return result
	var raw: Dictionary = json.data
	if _integer(raw.get("v"), 0, MAX_ID) != VERSION:
		result.why = WHY_VERSION
		return result
	var type: Variant = raw.get("t")
	if not type is String or not KNOWN_TYPES.has(type):
		result.why = WHY_BAD
		return result
	var types: Dictionary = TYPES[side]
	if not types.has(type):
		result.why = WHY_NOT_ALLOWED
		return result
	var specs: Dictionary = types[type]
	for name: String in specs:
		var kind: Field = specs[name]
		var value: Variant = _checked(raw.get(name), kind)
		if value == null:
			result.why = WHY_BAD
			result.fields.clear()
			return result
		result.fields[name] = value
	result.type = type
	return result


## The text of a message of `type` with `fields` as `side` sends it, or "" (with an error) when
## decode() would refuse it: a sender never puts on the wire what the other side drops.
static func encode(side: int, type: String, fields: Dictionary) -> String:
	var message := {"t": type, "v": VERSION}
	message.merge(fields)
	var text := JSON.stringify(message, "", true)
	var check := decode(text.to_ascii_buffer(), side)
	if not check.ok() or text.to_ascii_buffer().get_string_from_ascii() != text:
		push_error("signal: refused to encode %s from side %d: %s" % [type, side, check.why])
		return ""
	return text


## The whole message (type and "v" included) as a Dictionary, for transcripts and the router.
static func as_message(decoded: Decoded) -> Dictionary:
	var message: Dictionary = {"t": decoded.type, "v": VERSION}
	message.merge(decoded.fields)
	return message


## The content hash (an s64) as the 16 hex digits "found" and "open" carry: JSON numbers lose an
## s64's low bits in JavaScript.
static func content_text(fingerprint: int) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, fingerprint)
	return bytes.hex_encode()


static func content_hash(text: String) -> int:
	return text.hex_decode().decode_s64(0)


## A random room code from `random`: the service's own, never a client's.
static func random_code(random: RandomNumberGenerator) -> String:
	var code := ""
	for i: int in CODE_LENGTH:
		code += CODE_ALPHABET[random.randi_range(0, CODE_ALPHABET.length() - 1)]
	return code


static func is_code(value: Variant) -> bool:
	if not value is String:
		return false
	var text: String = value
	if text.length() != CODE_LENGTH:
		return false
	for character: String in text:
		if not CODE_ALPHABET.contains(character):
			return false
	return true


## The field checked against its kind, as the receiver should hold it, or null.
static func _checked(value: Variant, kind: Field) -> Variant:
	match kind:
		Field.INT:
			return _integer(value, 0, MAX_ID)
		Field.U16:
			return _integer(value, 0, 65535)
		Field.ID:
			return _integer(value, 1, MAX_ID)
		Field.MAX_JOINERS:
			return _integer(value, 1, MAX_JOINERS)
		Field.INDEX:
			return _integer(value, 0, 255)
		Field.CODE:
			return value if is_code(value) else null
		Field.CONTENT:
			if value is String and (value as String).length() == 16:
				return value if _is_lower_hex(value as String) else null
			return null
		Field.SDP:
			return _text(value, 1, MAX_SDP, true)
		Field.MID:
			return _text(value, 0, MAX_MID, false)
		Field.CAND:
			return _text(value, 0, MAX_CAND, false)
		Field.WHY:
			return _text(value, 1, MAX_WHY, false)
		Field.ICE:
			return _ice_servers(value)
	return null


## A JSON number with no fraction within [low, high] as an int, or null. JSON numbers parse as
## floats; an int is accepted too, for fields built in GDScript.
static func _integer(value: Variant, low: int, high: int) -> Variant:
	var number := 0
	if value is int:
		number = value
	elif value is float:
		var real: float = value
		if not is_finite(real) or real != floorf(real) or real < low or real > high:
			return null
		number = int(real)
	else:
		return null
	if number < low or number > high:
		return null
	return number


## A string of printable ASCII of `low` to `high` characters, or null. SDP alone has line breaks.
static func _text(value: Variant, low: int, high: int, lines: bool) -> Variant:
	if not value is String:
		return null
	var text: String = value
	if text.length() < low or text.length() > high:
		return null
	for at: int in text.length():
		var code := text.unicode_at(at)
		if code < 0x20 or code > 0x7E:
			if not (lines and (code == 0x0A or code == 0x0D)):
				return null
	return text


static func _is_lower_hex(text: String) -> bool:
	for character: String in text:
		if not "0123456789abcdef".contains(character):
			return false
	return true


## The ICE servers rebuilt from known keys only ("urls", "username", "credential"), or null.
static func _ice_servers(value: Variant) -> Variant:
	if not value is Array or (value as Array).size() > MAX_ICE_SERVERS:
		return null
	var servers: Array = []
	for entry: Variant in value:
		if not entry is Dictionary:
			return null
		var raw: Dictionary = entry
		var urls_value: Variant = raw.get("urls")
		if not urls_value is Array:
			return null
		var raw_urls: Array = urls_value
		if raw_urls.is_empty() or raw_urls.size() > MAX_ICE_URLS:
			return null
		var urls: Array = []
		for url: Variant in raw_urls:
			var checked: Variant = _text(url, 1, MAX_ICE_TEXT, false)
			if checked == null or not _ice_scheme(checked as String):
				return null
			urls.append(checked)
		var server := {"urls": urls}
		for key: String in ["username", "credential"]:
			if raw.has(key):
				var text: Variant = _text(raw[key], 0, MAX_ICE_TEXT, false)
				if text == null:
					return null
				server[key] = text
		servers.append(server)
	return servers


static func _ice_scheme(url: String) -> bool:
	for scheme: String in ["stun:", "stuns:", "turn:", "turns:"]:
		if url.begins_with(scheme):
			return true
	return false


static func _printable(bytes: PackedByteArray) -> bool:
	for byte: int in bytes:
		if (byte < 0x20 or byte > 0x7E) and byte != 0x09 and byte != 0x0A and byte != 0x0D:
			return false
	return true
