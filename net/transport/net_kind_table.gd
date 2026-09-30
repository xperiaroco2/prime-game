class_name NetKindTable
extends RefCounted
## The one table that binds each message kind on the wire to its lane (ENet channel and
## reliability), the direction it may travel and its payload cap. The frame header carries the
## kind (NetFrame); decoding rejects a packet that breaks its row. The game's rows live in game();
## tests build their own tables.

## How a kind travels. RELIABLE: channel 0, reliable and ordered (intents, events). LATEST:
## channel 0, unreliable ordered, a late copy is dropped (state where only the newest matters);
## the receiver gets at most the newest message per peer and kind per poll (NetTransport), so a
## LATEST message must stand alone: nothing may be lost when a newer one replaces it.
## VOICE: its own channel 1, unreliable UNORDERED: an ordered lane would drop reordered frames
## before the jitter buffer sees them (ARCHITECTURE §4, voice ADR).
enum Lane { RELIABLE, LATEST, VOICE }
## Who may send a kind. A packet travelling the other way is rejected.
enum Direction { HOST_TO_CLIENT = 1, CLIENT_TO_HOST = 2, BOTH = 3 }

## Kinds are one byte; 0 is never valid, so a zeroed buffer is not a message.
const MIN_KIND := 1
const MAX_KIND := 255
## The largest payload any kind may declare (the frame's u16 length field allows more).
const MAX_PAYLOAD := 8192
## Unreliable payloads must fit one ENet packet (MTU 1392): a fragmented unreliable packet is lost
## whole when any fragment is, and arrives without its unsequenced flag.
const MAX_UNRELIABLE_PAYLOAD := 1024
## User channels a client asks ENet for: VOICE is channel 1. The server asks for none
## (EnetTransport, godotengine/godot#123963).
const CHANNEL_COUNT := 1

var _rows: Dictionary[int, Row] = {}


class Row:
	var lane := Lane.RELIABLE
	var direction := Direction.BOTH
	var max_payload: int

	func _init(row_lane: Lane, row_direction: Direction, row_max_payload: int) -> void:
		lane = row_lane
		direction = row_direction
		max_payload = row_max_payload


## The game's table. Empty until the message schemas land (#32, M3): each schema adds its row here
## and to ARCHITECTURE §4 in the same PR.
static func game() -> NetKindTable:
	return NetKindTable.new()


static func channel_of(lane: Lane) -> int:
	return 1 if lane == Lane.VOICE else 0


static func mode_of(lane: Lane) -> MultiplayerPeer.TransferMode:
	match lane:
		Lane.RELIABLE:
			return MultiplayerPeer.TRANSFER_MODE_RELIABLE
		Lane.LATEST:
			return MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
		_:
			return MultiplayerPeer.TRANSFER_MODE_UNRELIABLE


## Adds a row. ERR_INVALID_PARAMETER for a kind out of range or a cap above its lane's limit,
## ERR_ALREADY_EXISTS for a kind that has a row.
func add(kind: int, lane: Lane, direction: Direction, max_payload: int) -> Error:
	if kind < MIN_KIND or kind > MAX_KIND:
		return ERR_INVALID_PARAMETER
	if _rows.has(kind):
		return ERR_ALREADY_EXISTS
	var limit := MAX_PAYLOAD if lane == Lane.RELIABLE else MAX_UNRELIABLE_PAYLOAD
	if max_payload < 0 or max_payload > limit:
		return ERR_INVALID_PARAMETER
	_rows[kind] = Row.new(lane, direction, max_payload)
	return OK


func has(kind: int) -> bool:
	return _rows.has(kind)


## Whether the host (from_host) or a client may send this kind. False for an unknown kind.
func allows(kind: int, from_host: bool) -> bool:
	var row: Row = _rows.get(kind)
	if row == null:
		return false
	var needed := Direction.HOST_TO_CLIENT if from_host else Direction.CLIENT_TO_HOST
	return (row.direction & needed) != 0


## The lane of a known kind (check has() first).
func lane_of(kind: int) -> Lane:
	return _rows[kind].lane


## The payload cap of a kind; -1 for an unknown kind.
func payload_cap(kind: int) -> int:
	var row: Row = _rows.get(kind)
	return row.max_payload if row != null else -1
