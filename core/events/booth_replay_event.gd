class_name BoothReplayEvent
extends MatchEvent
## A photo booth session's frames, replayed to a joiner (#1474; ARCHITECTURE §3.5, §4.2, §9.5.29):
## JoinRules.hello sends one per print whose strips still exist (BoothSessions keeps its frames
## while any does), in print order, and one for the session running at the join if it took a frame
## already. It names the booth's `station` and the session's `strip` id, as BoothStep does; its
## `records` are the FLASH records in frame order (each frame's rows as BoothStep's `record`: peer,
## colour, position, facing, crouched, sneaking, posed, limp); `items` are the print's strips that
## exist now, in PRINTED's order, so the joiner binds each to these frames and renders it as a
## present player does. Empty `items`: the running session, whose later FLASH and PRINTED the joiner
## gets as everyone does. No sound and no slide-in: these are old frames.
##
## Audience: only the joiner. A record holds only what every lobby peer saw in the BoothStep FLASH
## (the body's colour, place, facing and pose bits) and the strips are items the Welcome lists:
## nothing hidden; it goes to the joiner alone because the others have it already.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY

## The joiner.
var peer: int
## The booth's station id.
var station: int
## The session's strip id.
var strip: int
## Each frame's rows (an Array[Dictionary] each), in frame order.
var records: Array = []
## The print's strips that exist now, in PRINTED's order; empty for the running session.
var items := PackedInt32Array()


func _init(joiner: int, station_id: int, strip_id: int) -> void:
	peer = joiner
	station = station_id
	strip = strip_id


func event_name() -> StringName:
	return &"BoothReplay"


func audience() -> Audience:
	return Audience.only(peer)


## `records` untyped, each frame an Array[Dictionary] (the wire decodes a list of lists so).
func to_dict() -> Dictionary:
	var frames: Array = []
	for rows: Array in records:
		var copied: Array[Dictionary] = []
		for row: Dictionary in rows:
			copied.append(row.duplicate(true))
		frames.append(copied)
	return {
		"peer": peer,
		"station": station,
		"strip": strip,
		"records": frames,
		"items": items.duplicate(),
	}
