class_name LobbyBeacon
extends RefCounted
## The lobbies nearby (#1316; ARCHITECTURE §4.9): a finder on the local network asks, every host of
## a lobby answers, over UDP on PORT, apart from the game's wire (§4.3) and its transports. One
## datagram each way, little-endian:
## - **Query** (finder → broadcast and 127.0.0.1, on PORT): MAGIC, VERSION, `kind` QUERY, the
##   query's number (u32, the finder's own, answered back so it times the round trip).
## - **Answer** (host → the asker's address and port): MAGIC, VERSION, `kind` ANSWER, the query's
##   number, the host's number (u32, drawn anew each time a responder starts: one host
##   answering on two addresses is one lobby), the game's protocol (u16, WireSchema.VERSION:
##   another build's lobby is not listed), the game port (u16, 0 for none: a code host is
##   joined by its code), the players and the most (u8 each), the lobby's name and the host's
##   name (a u8 byte count and UTF-8 each, the name "" for the default `lobby.default_name`),
##   the room's code (a u8 count, 0 or the 6 characters of SignalCodec's alphabet).
## Decoding is defensive (net/CLAUDE.md): any other size, magic, version, kind, count, a name over
## its cap or not a wire `name` (WireText.utf8_problem, checked before any decode) or a code not of
## the alphabet makes null; nothing in a packet is trusted beyond being shown and offered for
## Join, which then runs the game's own checks (Hello, the room). The encoder refuses the same.
## Everything an answer carries is public in the lobby anyway: its name, its host, its players.

enum Kind { QUERY = 1, ANSWER = 2 }

## The discovery port (UDP): beside the game's default 24600 (LaunchOptions.DEFAULT_PORT).
const PORT := 24599
const MAGIC := 0x4C47_5250  # "PRGL" little-endian.
const VERSION := 1
## A query's whole size, and an answer's least and largest (names at their caps in UTF-8, the code).
const QUERY_SIZE := 10
const ANSWER_FIXED := 23
## The names' most characters: core/'s LobbyName.MAX_CHARS and PlayerNames.MAX_CHARS (net/ names
## no core/ class; a test pins them), and their most bytes, WireField's.
const LOBBY_CHARS := 20
const HOST_CHARS := 16
const NAME_BYTES := WireField.NAME_MAX_BYTES
const ANSWER_MAX := ANSWER_FIXED + 2 * NAME_BYTES + 6


## A host's answer: what a finder lists (the address is the packet's, not the answer's).
class Answer:
	extends RefCounted
	var query := 0
	var host := 0
	var protocol := 0
	var port := 0
	var players := 0
	var most := 0
	var lobby_name := ""
	var host_name := ""
	var code := ""

	## Whether a joiner fits: fewer players than the most.
	func has_room() -> bool:
		return players < most


static func query(number: int) -> PackedByteArray:
	var out := _head(Kind.QUERY)
	out.put_u32(number)
	return out.data_array


## `of` as an answer's bytes; empty, with an error, for what read_answer would refuse
## (net/CLAUDE.md: the encoder refuses, it never cuts or changes).
static func answer(of: Answer) -> PackedByteArray:
	var problem := answer_problem(of)
	if not problem.is_empty():
		push_error("LobbyBeacon.answer: %s" % problem)
		return PackedByteArray()
	var out := _head(Kind.ANSWER)
	out.put_u32(of.query)
	out.put_u32(of.host)
	out.put_u16(of.protocol)
	out.put_u16(of.port)
	out.put_u8(of.players)
	out.put_u8(of.most)
	for text: String in [of.lobby_name, of.host_name]:
		var bytes := text.to_utf8_buffer()
		out.put_u8(bytes.size())
		out.put_data(bytes)
	var code := of.code.to_ascii_buffer()
	out.put_u8(code.size())
	out.put_data(code)
	return out.data_array


## Why `of` cannot be sent ("" when it can): the decoder's rules.
static func answer_problem(of: Answer) -> String:
	if of.query < 0 or of.query > 0xFFFF_FFFF or of.host < 0 or of.host > 0xFFFF_FFFF:
		return "a number out of u32"
	if of.protocol < 0 or of.protocol > 0xFFFF or of.port < 0 or of.port > 0xFFFF:
		return "the protocol or the port out of u16"
	if of.most < 1 or of.most > 255 or of.players < 0 or of.players > of.most:
		return "players %d of %d" % [of.players, of.most]
	if not _is_name(of.lobby_name, LOBBY_CHARS) or not _is_name(of.host_name, HOST_CHARS):
		return "a name that is no wire name or over its cap"
	if not of.code.is_empty() and not is_code(of.code):
		return "a code off the alphabet"
	return ""


## The query's number of `bytes`, or -1 when they are no query.
static func query_number(bytes: PackedByteArray) -> int:
	if bytes.size() != QUERY_SIZE:
		return -1
	var reader := _reader(bytes, Kind.QUERY)
	return reader.get_u32() if reader != null else -1


## The answer in `bytes`, or null when they are none (see the class's rules).
static func read_answer(bytes: PackedByteArray) -> Answer:
	if bytes.size() < ANSWER_FIXED or bytes.size() > ANSWER_MAX:
		return null
	var reader := _reader(bytes, Kind.ANSWER)
	if reader == null:
		return null
	var got := Answer.new()
	got.query = reader.get_u32()
	got.host = reader.get_u32()
	got.protocol = reader.get_u16()
	got.port = reader.get_u16()
	got.players = reader.get_u8()
	got.most = reader.get_u8()
	var lobby: Variant = _text(reader, LOBBY_CHARS)
	var host: Variant = _text(reader, HOST_CHARS)
	if lobby == null or host == null:
		return null
	got.lobby_name = lobby
	got.host_name = host
	var count := reader.get_u8() if reader.get_available_bytes() >= 1 else -1
	if count != 0 and count != SignalCodec.CODE_LENGTH:
		return null
	if reader.get_available_bytes() != count:
		return null
	if count > 0:
		var code: PackedByteArray = reader.get_data(count)[1]
		# Only the code alphabet's bytes: nothing else is decoded as text.
		var alphabet := SignalCodec.CODE_ALPHABET.to_ascii_buffer()
		for byte: int in code:
			if not alphabet.has(byte):
				return null
		got.code = code.get_string_from_ascii()
	if got.most < 1 or got.players > got.most:
		return null
	return got


static func is_code(text: String) -> bool:
	return text.length() == SignalCodec.CODE_LENGTH and SignalCodec.is_code(text)


static func _head(kind: Kind) -> StreamPeerBuffer:
	var out := StreamPeerBuffer.new()
	out.put_u32(MAGIC)
	out.put_u8(VERSION)
	out.put_u8(kind)
	return out


## A reader past the head of `bytes` when it is this version's `kind`, else null.
static func _reader(bytes: PackedByteArray, kind: Kind) -> StreamPeerBuffer:
	var reader := StreamPeerBuffer.new()
	reader.data_array = bytes
	if reader.get_u32() != MAGIC or reader.get_u8() != VERSION or reader.get_u8() != kind:
		return null
	return reader


## Whether `text` is a wire `name` of at most `most_chars` characters.
static func _is_name(text: String, most_chars: int) -> bool:
	return text.length() <= most_chars and WireText.is_name(text)


## A u8 byte count and that much UTF-8 of a wire `name` (WireText.utf8_problem before decoding,
## so no engine error line), at most `most_chars` characters; null when it is cut or no name.
static func _text(reader: StreamPeerBuffer, most_chars: int) -> Variant:
	if reader.get_available_bytes() < 1:
		return null
	var count := reader.get_u8()
	if count > NAME_BYTES or reader.get_available_bytes() < count:
		return null
	var bytes: PackedByteArray = reader.get_data(count)[1]
	if WireText.utf8_problem(bytes) >= 0:
		return null
	var text := bytes.get_string_from_utf8()
	if text.length() > most_chars:
		return null
	return text
