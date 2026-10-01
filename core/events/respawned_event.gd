class_name RespawnedEvent
extends MatchEvent
## A dead player came back (ARCHITECTURE §4.2, §5; vision revision 1, V6): living again at the
## respawn marker `position`, with its role, full health and stamina and empty hands, invulnerable
## for PlayerRules.invulnerable_s. It removes the player's body (E26: no event of its own). Public,
## like the body it removes and the avatar that appears; no field names how it died. Emitted after
## the player became living, before its Correction. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
## The respawn marker it stands on.
var position: Vector3


func _init(respawned: int, at: Vector3) -> void:
	peer = respawned
	position = at


func event_name() -> StringName:
	return &"Respawned"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "position": position}
