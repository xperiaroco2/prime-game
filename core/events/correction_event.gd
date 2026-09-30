class_name CorrectionEvent
extends MatchEvent
## The host's position for one player, with a new epoch (ARCHITECTURE §4.2, §7): after a rejected
## MoveClaim (2d) or a placement (§3.2). Private, because a public epoch would count a player's
## corrections, which mostly come from hidden stamina. Audience: only that player.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY

var peer: int
var epoch: int
var position: Vector3
var velocity: Vector3


func _init(to_peer: int, new_epoch: int, at: Vector3, moving: Vector3) -> void:
	peer = to_peer
	epoch = new_epoch
	position = at
	velocity = moving


func event_name() -> StringName:
	return &"Correction"


func audience() -> Audience:
	return Audience.only(peer)


func to_dict() -> Dictionary:
	return {"epoch": epoch, "position": position, "velocity": velocity}
