class_name DisconnectingEvent
extends MatchEvent
## Why the host is about to disconnect a player (ARCHITECTURE §3.5, §4.2; #119, the M4 ADR's E21):
## emitted right before the DisconnectPeer it explains, so the player's client ends with this
## reason instead of host_lost. Today only the loading deadline (`load_deadline`). Audience: only
## that player; `peer` is its subject, as CorrectionEvent's, although the payload names none.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY

## The player did not confirm its map load before Loading's deadline (§3.2).
const LOAD_DEADLINE := &"load_deadline"

var peer: int
var reason: StringName


func _init(to_peer: int, why: StringName) -> void:
	peer = to_peer
	reason = why


func event_name() -> StringName:
	return &"Disconnecting"


func audience() -> Audience:
	return Audience.only(peer)


func to_dict() -> Dictionary:
	return {"reason": reason}
