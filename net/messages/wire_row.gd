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


## Every name a payload of this row may hold (the wire-only fields left out).
func field_names() -> PackedStringArray:
	var found := PackedStringArray()
	for field: WireField in fields:
		found.append_array(field.keys())
	return found
