class_name WireSchema
extends RefCounted
## The one declarative table of ARCHITECTURE §4.3 (E4) and the codec of §4.4 that walks it: every
## intent, debug command, event, the snapshot and the voice frames, each a row of kind, name,
## direction, lane, cap and fields with their wire types. NetKindTable.game() is built from it.
##
## encode() refuses, with an error in the log, whatever decode() would reject and any payload over
## its cap: it never truncates. decode() trusts nothing and returns null at the first problem;
## nothing of a rejected message may reach core/. Field names are core/'s, as strings: an intent
## decodes to its MatchCommand's args (and seq), an event to its name and a Dictionary equal to
## its to_dict(), with the same Variant types.

## The protocol version: the same number as core/'s JoinRules.PROTOCOL_VERSION (a test pins them).
## Every change to a row (a kind, lane, direction, cap, field, its type or its order) bumps it.
const VERSION := 6

## Frozen rows (§4.3): any client can send its version and read Rejected(wrong_version).
const HELLO := 1
const REJECTED := 32

## Kind ranges (§4.3): 0 is the transport's ADMIT.
const FIRST_INTENT := 1
const FIRST_DEBUG := 24
const FIRST_EVENT := 32
const FIRST_STATE := 96
const FIRST_VOICE := 112
const LAST_VOICE := 127

## The wire's maxima (§4.3): they bound the decoder, not the payload; WireBudget checks the content.
const MAX_PLAYERS := 16
## A snapshot never holds the viewer's own avatar.
const MAX_AVATARS := MAX_PLAYERS - 1
## Settings, spawn tags and station kinds per map.
const MAX_ENTRIES := 32
const MAX_TASK_TYPES := 16
const MAX_SHORTFALLS := 32
## One 20 ms Opus frame.
const MAX_OPUS := 500

## Built once per build kind: the rows never change at run time.
static var _built: Dictionary[bool, WireSchema] = {}

var _by_kind: Dictionary[int, WireRow] = {}
var _by_name: Dictionary[StringName, WireRow] = {}


## An encoded payload, or why it was refused (`payload` then holds what was written, so WireBudget
## can name the size of a payload over its cap).
class Encoded:
	var kind := 0
	var payload := PackedByteArray()
	var problem := ""


## The game's table. `debug`: a debug build's, the only one with the debug commands (kinds 24 to
## 31, E17): a release build neither sends nor decodes them.
static func game(debug: bool) -> WireSchema:
	if not _built.has(debug):
		var schema := WireSchema.new()
		for each: WireRow in _intents() + _events() + _state_and_voice():
			schema._add(each)
		if debug:
			for each: WireRow in _debug_commands():
				schema._add(each)
		_built[debug] = schema
	return _built[debug]


## Every row in kind order.
func rows() -> Array[WireRow]:
	var kinds := _by_kind.keys()
	kinds.sort()
	var found: Array[WireRow] = []
	for kind: int in kinds:
		found.append(_by_kind[kind])
	return found


## The row of a kind, or null.
func row(kind: int) -> WireRow:
	return _by_kind.get(kind)


## The row of a name, or null.
func row_named(row_name: StringName) -> WireRow:
	return _by_name.get(row_name)


## The kind of a name; 0 (never a message) for an unknown one.
func kind_of(row_name: StringName) -> int:
	var found := row_named(row_name)
	return found.kind if found != null else 0


## The transport's table: each row's lane, direction and cap.
func kind_table() -> NetKindTable:
	var table := NetKindTable.new()
	for each: WireRow in rows():
		var added := table.add(each.kind, each.lane, each.direction, each.cap)
		if added != OK:
			# Logged too: a release build strips the assert and would drop the row silently.
			push_error("wire: row %d does not fit NetKindTable" % each.kind)
		assert(added == OK, "wire: row %d does not fit NetKindTable" % each.kind)
	return table


## The payload of `message`, or an empty array after logging why it was refused: an unknown name,
## a missing or undeclared field, a value its wire type rejects, or a payload over the cap. No row
## has an empty payload, so empty always means refused.
func encode(message: WireMessage) -> PackedByteArray:
	var encoded := write(message)
	if not encoded.problem.is_empty():
		push_error("wire: refused to encode %s: %s" % [message.name, encoded.problem])
		return PackedByteArray()
	return encoded.payload


## encode() without the log: the payload and the problem, for callers that report it themselves.
func write(message: WireMessage) -> Encoded:
	var encoded := Encoded.new()
	var found := row_named(message.name)
	if found == null:
		encoded.problem = "no row named %s" % message.name
		return encoded
	encoded.kind = found.kind
	var writer := WireWriter.new()
	encoded.problem = WireField.write_all(found.fields, message.fields, writer, message)
	encoded.payload = writer.bytes
	if encoded.problem.is_empty() and writer.bytes.size() > found.cap:
		encoded.problem = "%d bytes, over its cap of %d" % [writer.bytes.size(), found.cap]
	return encoded


## The message in a payload of `kind`, or null when anything is wrong with it. NetFrame has
## checked the kind's direction, lane and cap.
func decode(kind: int, payload: PackedByteArray) -> WireMessage:
	var reader := WireReader.new(payload)
	var message := _read(kind, reader)
	return null if reader.failed else message


## Why decode() rejects a payload; empty when it does not.
func explain(kind: int, payload: PackedByteArray) -> String:
	var reader := WireReader.new(payload)
	_read(kind, reader)
	return reader.problem


func _read(kind: int, reader: WireReader) -> WireMessage:
	var found := row(kind)
	if found == null:
		reader.fail("no row of kind %d" % kind)
		return null
	var message := WireMessage.new(found.name)
	message.kind = kind
	var fields := found.fields
	if kind == HELLO:
		# Two steps (§4.3): another version is its version alone, whatever follows it.
		var version := reader.u16()
		if reader.failed:
			return null
		message.fields["version"] = version
		if version != VERSION:
			return message
		var after_version: Array[WireField] = []
		after_version.assign(fields.slice(1))
		fields = after_version
	WireField.read_all(fields, reader, message.fields, message)
	if not reader.failed and not reader.at_end():
		reader.fail("%d bytes after the last field" % reader.left())
	return message


func _add(added: WireRow) -> void:
	assert(not _by_kind.has(added.kind) and not _by_name.has(added.name))
	_by_kind[added.kind] = added
	_by_name[added.name] = added


static func _intents() -> Array[WireRow]:
	var claim_flags := PackedStringArray(["sprint", "moving", "on_floor"])
	var settings := WireField.map(
		"settings", _id(""), WireField.setting("", MAX_TASK_TYPES), MAX_ENTRIES, false
	)
	var has_map := WireField.when("has_map", [_of("map", WireField.Type.PATH)])
	var hello := _up(HELLO, &"Hello", 8192, [_u16("version"), _of("content", WireField.Type.S64)])
	var change := _up(3, &"ChangeSettings", 2048, [_seq(), settings, has_map])
	change.content_sized = true
	return [
		hello,
		_up(2, &"SetReady", 5, [_seq(), _bool("ready")]),
		change,
		_up(4, &"LoadAck", 8, [_seq(), _u32("match_id")]),
		_row(
			5,
			&"MoveClaim",
			NetKindTable.Direction.CLIENT_TO_HOST,
			NetKindTable.Lane.LATEST,
			47,
			[
				_u32("epoch"),
				_u32("client_tick"),
				_vec3("position"),
				_vec3("velocity"),
				_vec3("facing"),
				WireField.bits(claim_flags),
				_u16("jumps"),
			]
		),
		_up(6, &"PickUp", 6, [_seq(), _of("item", WireField.Type.ITEM)]),
		_up(7, &"PutDown", 16, [_seq(), _vec3("facing")]),
		_up(8, &"Use", 16, [_seq(), _vec3("facing")]),
		_up(9, &"ReturnToLobby", 4, [_seq()]),
		_up(10, &"Raise", 8, [_seq(), _peer("target")]),
		_up(11, &"StopRaise", 4, [_seq()]),
		_up(12, &"GiveUp", 4, [_seq()]),
		_up(13, &"Swap", 4, [_seq()]),
	]


## Debug builds only (E17): server/ takes them from the host's own client and turns each into the
## command it names. The role decodes as a String, as Match reads it; false clears it ("").
## ForceClock names the sender itself (the host's own player) in `peer`, as every debug kind
## names a player.
static func _debug_commands() -> Array[WireRow]:
	var role := WireField.when("has_role", [WireField.id("role", true)], {"role": ""})
	return [
		_up(24, &"ForceRole", 42, [_seq(), WireField.target_peer(), role]),
		_up(25, &"ForceClock", 10, [_seq(), WireField.target_peer(), _u16("seconds")]),
	]


static func _events() -> Array[WireRow]:
	var roster_entry := WireField.record("", [_peer("peer"), _text("name"), _bool("ready")])
	var numbers := _numbers("settings")
	var welcome := _down(
		33,
		&"Welcome",
		2048,
		[
			_peer("peer"),
			_vec3("spot"),
			_u32("epoch"),
			WireField.list("roster", roster_entry, MAX_PLAYERS),
			numbers,
			_path("map"),
			_id("phase"),
			WireField.map("positions", _peer(""), _vec3(""), MAX_PLAYERS),
		]
	)
	var id_sets := WireField.map(
		"id_sets",
		_id(""),
		WireField.list("", _id(""), MAX_TASK_TYPES, TYPE_PACKED_STRING_ARRAY),
		MAX_ENTRIES
	)
	var settings_changed := _down(
		37,
		&"SettingsChanged",
		8192,
		[
			_numbers("settings"),
			id_sets,
			_path("map"),
			_of("players", WireField.Type.U8),
			_numbers("needed_markers"),
			_numbers("map_markers"),
			_numbers("needed_colours"),
			_numbers("palettes"),
			WireField.list(
				"shortfalls", _of("", WireField.Type.NOTE), MAX_SHORTFALLS, TYPE_PACKED_STRING_ARRAY
			),
		]
	)
	var spots := WireField.map("spots", _peer(""), _vec3(""), MAX_PLAYERS)
	var players_placed := _down(40, &"PlayersPlaced", 257, [spots])
	var load_match := _down(
		41, &"LoadMatch", 2048, [_u32("match_id"), _path("map"), _numbers("settings")]
	)
	var peers := WireField.list("peers", _peer(""), MAX_PLAYERS, TYPE_PACKED_INT32_ARRAY)
	var teammates := _down(45, &"Teammates", 98, [_id("role"), peers])
	var station_placed := _down(
		46,
		&"StationPlaced",
		63,
		[_station("station"), _id("kind"), _colour("colour"), _vec3("position")]
	)
	var package := WireField.when("has_station", [_station("station"), _colour("colour")])
	var item_spawned := _down(
		47, &"ItemSpawned", 66, [_item("item"), _id("kind"), _vec3("position"), package]
	)
	for sized: WireRow in [
		welcome,
		settings_changed,
		players_placed,
		load_match,
		teammates,
		station_placed,
		item_spawned
	]:
		sized.content_sized = true
	return [
		_down(REJECTED, &"Rejected", 37, [_u32("seq"), _id("reason")]),
		welcome,
		_down(34, &"PlayerJoined", 81, [_peer("peer"), _text("name"), _vec3("spot")]),
		_down(35, &"PlayerLeft", 4, [_peer("peer")]),
		_down(36, &"ReadyChanged", 5, [_peer("peer"), _bool("ready")]),
		settings_changed,
		_down(38, &"PhaseChanged", 37, [_id("phase"), WireField.maybe("end_tick", _tick())]),
		_down(39, &"CountdownCancelled", 33, [_id("reason")]),
		players_placed,
		load_match,
		_down(42, &"PlayerLoaded", 4, [_peer("peer")]),
		_down(43, &"RoundStarted", 4, [_of("start_tick", _tick())]),
		_down(44, &"RoleAssigned", 33, [_id("role")]),
		teammates,
		station_placed,
		item_spawned,
		_down(
			48,
			&"ItemPickedUp",
			8,
			[_peer("peer"), _item("item"), WireField.maybe("belted", WireField.Type.ITEM)]
		),
		_down(49, &"ItemPlaced", 47, [_item("item"), _vec3("position"), _id("cause")]),
		_down(50, &"PackageDelivered", 4, [_item("item"), _station("station")]),
		_down(51, &"TaskProgress", 4, [_u16("done"), _u16("total")]),
		_down(52, &"Swung", 16, [_peer("peer"), _vec3("facing")]),
		_down(53, &"Damaged", 8, [_s32("amount"), _s32("health")]),
		_down(54, &"SelfStatus", 9, [_s32("health"), _s32("stamina"), _bool("sprint_available")]),
		_down(55, &"Died", 16, [_peer("peer"), _vec3("position")]),
		_down(56, &"Correction", 28, [_u32("epoch"), _vec3("position"), _vec3("velocity")]),
		_down(57, &"MatchEnded", 33, [_id("side")]),
		_down(58, &"Disconnecting", 33, [_id("reason")]),
		_down(59, &"KnockedDown", 16, [_peer("peer"), _vec3("position")]),
		_down(60, &"Respawned", 16, [_peer("peer"), _vec3("position")]),
		_down(61, &"RaiseStarted", 8, [_peer("raiser"), _peer("target")]),
		_down(62, &"RaiseStopped", 8, [_peer("raiser"), _peer("target")]),
		_down(63, &"Revived", 4, [_peer("peer")]),
		_down(64, &"Swapped", 4, [_peer("peer")]),
		_down(
			65,
			&"TaskState",
			38,
			[_of("task", WireField.Type.U8), _id("type"), _u16("done"), _u16("total")]
		),
	]


static func _state_and_voice() -> Array[WireRow]:
	var avatar := (
		WireField
		. record(
			"",
			[
				_vec3("position"),
				_vec3("velocity"),
				_vec3("facing"),
				WireField.bits(PackedStringArray(["downed", "invulnerable"])),
				WireField.maybe("held_item", WireField.Type.ITEM),
				WireField.maybe("belt_item", WireField.Type.ITEM),
			]
		)
	)
	var avatars := WireField.map("avatars", _peer(""), avatar, MAX_AVATARS, false)
	var snapshot := _row(
		96,
		&"Snapshot",
		NetKindTable.Direction.HOST_TO_CLIENT,
		NetKindTable.Lane.LATEST,
		1024,
		[_of("tick", _tick()), avatars]
	)
	var voice_up := _row(
		112,
		&"VoiceUp",
		NetKindTable.Direction.CLIENT_TO_HOST,
		NetKindTable.Lane.VOICE,
		2 + MAX_OPUS,
		[_u16("seq"), WireField.opus("opus", MAX_OPUS)]
	)
	var voice_down := _row(
		113,
		&"VoiceDown",
		NetKindTable.Direction.HOST_TO_CLIENT,
		NetKindTable.Lane.VOICE,
		10 + MAX_OPUS,
		[_peer("speaker"), _u16("seq"), _of("tick", _tick()), WireField.opus("opus", MAX_OPUS)]
	)
	return [snapshot, voice_up, voice_down]


static func _row(
	kind: int,
	row_name: StringName,
	direction: NetKindTable.Direction,
	lane: NetKindTable.Lane,
	cap: int,
	fields: Array[WireField]
) -> WireRow:
	return WireRow.new(kind, row_name, direction, lane, cap, fields)


## A RELIABLE client-to-host row.
static func _up(kind: int, row_name: StringName, cap: int, fields: Array[WireField]) -> WireRow:
	return _row(
		kind,
		row_name,
		NetKindTable.Direction.CLIENT_TO_HOST,
		NetKindTable.Lane.RELIABLE,
		cap,
		fields
	)


## A RELIABLE host-to-client row (every event).
static func _down(kind: int, row_name: StringName, cap: int, fields: Array[WireField]) -> WireRow:
	return _row(
		kind,
		row_name,
		NetKindTable.Direction.HOST_TO_CLIENT,
		NetKindTable.Lane.RELIABLE,
		cap,
		fields
	)


static func _of(field_name: String, type: WireField.Type) -> WireField:
	return WireField.of(field_name, type)


static func _seq() -> WireField:
	return WireField.seq_number()


static func _u16(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.U16)


static func _u32(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.U32)


static func _s32(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.S32)


static func _bool(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.BOOL)


static func _vec3(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.VEC3)


static func _colour(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.COLOUR)


static func _peer(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.PEER)


static func _item(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.ITEM)


static func _station(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.STATION)


static func _tick() -> WireField.Type:
	return WireField.Type.TICK


static func _id(field_name: String) -> WireField:
	return WireField.id(field_name)


static func _path(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.PATH)


static func _text(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.TEXT)


## A map<id, s32>: whole-number settings, markers or colours per id.
static func _numbers(field_name: String) -> WireField:
	return WireField.map(field_name, _id(""), _s32(""), MAX_ENTRIES)
