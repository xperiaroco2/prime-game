class_name LaunchBodyEvent
extends MatchEvent
## A directive (ARCHITECTURE §4.2; the knockdown rework's §4, KE13): a knockdown on a map
## PlayerRules.motion_maps lists started a motion, and server/ starts the host's body of `peer`
## (HostBodies): the crouching player's capsule, upright, its lowest point at `origin` (the last
## accepted position), with `velocity` (the launch, zero included). `epoch` is the knockdown's
## (its Correction's): server/ names it in every BodyMoved of this body, so a report of a body freed
## earlier never passes for the next knockdown's. A replay ignores it (it runs no physics).
## Audience: server, no peer.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.SERVER

var peer: int
var epoch: int
var origin: Vector3
var velocity: Vector3


func _init(downed: int, knockdown_epoch: int, from: Vector3, launch: Vector3) -> void:
	peer = downed
	epoch = knockdown_epoch
	origin = from
	velocity = launch


func event_name() -> StringName:
	return &"LaunchBody"


func audience() -> Audience:
	return Audience.server()


func to_dict() -> Dictionary:
	return {"peer": peer, "epoch": epoch, "origin": origin, "velocity": velocity}
