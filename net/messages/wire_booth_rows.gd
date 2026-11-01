class_name WireBoothRows
extends RefCounted
## The photo booth's event rows of WireSchema (ARCHITECTURE §4.3.4 rows 96 and 97): BoothStep
## (#1396) and a joiner's BoothReplay (#1474), which share the frame's record row. Split out of
## wire_schema.gd at its line limit, as WireCollection was out of wire_field.gd; WireSchema._events
## lists them in kind order.

const MAX_PLAYERS := WireSchema.MAX_PLAYERS
const MAX_BOOTH_FRAMES := WireSchema.MAX_BOOTH_FRAMES


## The photo booth's step (#1396): every field always, the ones a step does not use 0 or empty
## (BoothStepEvent). A record row is the lobby avatar's public look and pose: its peer, colour,
## position, facing and the crouched, sneaking, posed and limp flags; at most MAX_PLAYERS rows
## and MAX_PLAYERS strips, so its size is the schema's, not the content's.
static func step() -> WireRow:
	return _down(
		96,
		&"BoothStep",
		529,
		[
			WireField.of("station", WireField.Type.STATION),
			_u16("strip"),
			WireField.of("step", WireField.Type.U8),
			WireField.of("presser", WireField.Type.U32),
			WireField.of("frames", WireField.Type.U8),
			_u16("countdown"),
			_u16("gap"),
			WireField.of("frame", WireField.Type.U8),
			WireField.list("record", _frame_row(), MAX_PLAYERS),
			_items(),
		]
	)


## A booth session's frames for a joiner (#1474, BoothReplayEvent): the joiner, the booth, the
## session's strip id, its frames' records in frame order (each a BoothStep record) and the strips
## that exist now. Its cap is the schema's size at the maxima (MAX_BOOTH_FRAMES frames of
## MAX_PLAYERS rows, MAX_PLAYERS strips), under the reliable limit; a real print is far smaller.
static func replay() -> WireRow:
	return _down(
		97,
		&"BoothReplay",
		3890,
		[
			WireField.of("peer", WireField.Type.PEER),
			WireField.of("station", WireField.Type.STATION),
			_u16("strip"),
			WireField.list(
				"records", WireField.list("", _frame_row(), MAX_PLAYERS), MAX_BOOTH_FRAMES
			),
			_items(),
		]
	)


## One row of a booth frame's record (BoothStep, BoothReplay).
static func _frame_row() -> WireField:
	return (
		WireField
		. record(
			"",
			[
				WireField.of("peer", WireField.Type.PEER),
				WireField.of("colour", WireField.Type.U8),
				WireField.of("position", WireField.Type.VEC3),
				WireField.of("facing", WireField.Type.VEC3),
				WireField.bits(PackedStringArray(["crouched", "sneaking", "posed", "limp"])),
			]
		)
	)


## A RELIABLE host-to-client row (every event), as WireSchema's.
static func _down(kind: int, row_name: StringName, cap: int, fields: Array[WireField]) -> WireRow:
	return WireRow.new(
		kind,
		row_name,
		NetKindTable.Direction.HOST_TO_CLIENT,
		NetKindTable.Lane.RELIABLE,
		cap,
		fields
	)


## The strips' item ids, at most MAX_PLAYERS.
static func _items() -> WireField:
	var item := WireField.of("", WireField.Type.ITEM)
	return WireField.list("items", item, MAX_PLAYERS, TYPE_PACKED_INT32_ARRAY)


static func _u16(field_name: String) -> WireField:
	return WireField.of(field_name, WireField.Type.U16)
