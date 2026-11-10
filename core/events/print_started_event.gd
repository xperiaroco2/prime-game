class_name PrintStartedEvent
extends MatchEvent
## A drone starts printing a dead player back (#1489; ARCHITECTURE §4.2, §5): the player stands on
## the respawn marker `position`, printing from the feet up for `print_s` seconds, cannot be moved
## or hit until Respawned ends the print. It removes the player's body (E26: no event of its own):
## the return has begun, seen by everyone near. No field names how it died. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
## The respawn marker it is printed on.
var position: Vector3
## How long the print lasts, in seconds (Respawn.print_s).
var print_s: float


func _init(printed: int, at: Vector3, seconds: float) -> void:
	peer = printed
	position = at
	print_s = seconds


func event_name() -> StringName:
	return &"PrintStarted"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "position": position, "print_ms": roundi(print_s * 1000.0)}
