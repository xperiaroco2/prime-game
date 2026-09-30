class_name DisconnectPeerEvent
extends MatchEvent
## A directive (ARCHITECTURE §3.5, §4.2): server/ disconnects `peer`
## (`NetTransport.disconnect_peer`) after sending it what was emitted before, a Rejected with the
## reason for example. Emitted for
## a Hello with another protocol version or into a full lobby, a connection that completed while
## joins are refused, and a player who missed the loading deadline. The peer's later PeerLeft
## finds it gone and changes nothing. Audience: server, no peer.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.SERVER

var peer: int


func _init(to_disconnect: int) -> void:
	peer = to_disconnect


func event_name() -> StringName:
	return &"DisconnectPeer"


func audience() -> Audience:
	return Audience.server()


func to_dict() -> Dictionary:
	return {"peer": peer}
