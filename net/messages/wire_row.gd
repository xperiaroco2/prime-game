class_name WireRow
extends RefCounted
## One row of ARCHITECTURE §4.3: a kind byte, its name, the direction and lane it travels, its
## payload cap and its fields in wire order. WireSchema holds every row; NetKindTable.game() is
## built from them, so a kind's lane is declared once.

var kind: int
var name: StringName
var direction := NetKindTable.Direction.BOTH
var lane := NetKindTable.Lane.RELIABLE
var cap: int
var fields: Array[WireField] = []
## How big it gets depends on the content (ids, settings, map paths, max_players, shortfalls):
## WireBudget computes its worst case per game mode (§4.3, E16).
var content_sized := false


func _init(
	row_kind: int,
	row_name: StringName,
	row_direction: NetKindTable.Direction,
	row_lane: NetKindTable.Lane,
	row_cap: int,
	row_fields: Array[WireField],
) -> void:
	kind = row_kind
	name = row_name
	direction = row_direction
	lane = row_lane
	cap = row_cap
	fields = row_fields


## The most bytes the fields take at the wire's maxima (§4.3), whatever the cap.
func max_size() -> int:
	var total := 0
	for field: WireField in fields:
		total += field.max_size()
	return total


## The payload field named `field_name` (a wire-only slot never), or null.
func field_named(field_name: String) -> WireField:
	for field: WireField in fields:
		if field.slot == WireField.Slot.FIELD and field.name == field_name:
			return field
	return null


## Where the field named `field_name` starts in every payload of this row: the sum of the fixed
## sizes of the fields before it. -1 when it is no payload field of a fixed size, or a field
## before it varies in size. Lets a caller patch that field in an encoded payload without a byte
## index of its own (the host's voice relay writes each listener's seq, VoiceBatchEncoder).
func fixed_offset(field_name: String) -> int:
	return offset_among(fields, field_name)


## fixed_offset() over any fields in wire order: a row's, or a RECORD's parts.
static func offset_among(in_order: Array[WireField], field_name: String) -> int:
	var at := 0
	for field: WireField in in_order:
		var size := field.fixed_size()
		if field.slot == WireField.Slot.FIELD and field.name == field_name:
			return at if size > 0 else -1
		if size < 0:
			return -1
		at += size
	return -1


## Every name a payload of this row may hold (the wire-only fields left out).
func field_names() -> PackedStringArray:
	var found := PackedStringArray()
	for field: WireField in fields:
		found.append_array(field.keys())
	return found
