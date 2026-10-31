class_name BoothStepEvent
extends MatchEvent
## A step of the lobby's photo booth (#1396; GDD §3 "The photo booth"; ARCHITECTURE §4.2, §9.5.28):
## one event for the whole sequence, `step` telling which (the wire's event kinds have one free row,
## §4.3.4). Each names the booth's `station` and the session's `strip` (an id wrapping at 0x10000,
## BoothSessions), so a client binds the steps of one session together:
## - STARTED: an accepted Interact at the booth started a session: its `presser`, its `frames`, the
##   `countdown` to the first flash and the `gap` between flashes (ticks), so a client paces its
##   countdown display from host data; the flashes themselves come as FLASH on the host's clock.
## - FLASH: the flash `frame` (0 first) fired: its `record`, one row per living present player
##   inside the booth's cylinder at that tick, in peer order: `peer`, `colour`, `position`,
##   `facing`, `crouched`, `sneaking`, `posed` (the seated pose, false in the base lobby: the pose
##   wheel, #1227, adds its own) and `limp`. Read at the flash, so frame k holds the poses at k.
## - PRINTED: after the last flash, the strips' item ids (`items`, one per player in the frames who
##   is still present and alive, in peer order), each announced by the ItemSpawned right before it;
##   a client binds each strip to the session's FLASH records and renders it from them.
## - STOPPED: the session ended with no print: its presser left, the lobby ended (StopBooth), or no
##   player was in any frame.
## The fields a step does not use are 0 or empty.
##
## Audience: everyone. A record holds only what every lobby peer sees in the snapshots anyway (the
## body's colour, place, facing and pose bits); nothing hidden is in a frame, and no pixel crosses
## the wire (the photo ADR §3.3's pattern).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

const STARTED := 0
const FLASH := 1
const PRINTED := 2
const STOPPED := 3

## The booth's station id.
var station: int
## The session's strip id.
var strip: int
## STARTED, FLASH, PRINTED or STOPPED.
var step: int
## STARTED: who pressed.
var presser := 0
## STARTED: how many flashes.
var frames := 0
## STARTED: the ticks from the press to the first flash.
var countdown := 0
## STARTED: the ticks between two flashes.
var gap := 0
## FLASH: which flash, 0 first.
var frame := 0
## FLASH: the frame's rows.
var record: Array[Dictionary] = []
## PRINTED: the strips' item ids.
var items := PackedInt32Array()


func _init(station_id: int, strip_id: int, step_kind: int) -> void:
	station = station_id
	strip = strip_id
	step = step_kind


func event_name() -> StringName:
	return &"BoothStep"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {
		"station": station,
		"strip": strip,
		"step": step,
		"presser": presser,
		"frames": frames,
		"countdown": countdown,
		"gap": gap,
		"frame": frame,
		"record": record.duplicate(true),
		"items": items.duplicate(),
	}
