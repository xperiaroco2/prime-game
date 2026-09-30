class_name RoleAssignedEvent
extends MatchEvent
## A player's own role, dealt by DealRoles (ARCHITECTURE §3.3, §4.2). A role never leaves the host
## except to its player, and to the teammates of a role that knows them (Teammates, §5).
## Audience: only that player.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY

var peer: int
## A GameRole id of the mode.
var role: StringName


func _init(to_peer: int, role_id: StringName) -> void:
	peer = to_peer
	role = role_id


func event_name() -> StringName:
	return &"RoleAssigned"


func audience() -> Audience:
	return Audience.only(peer)


func to_dict() -> Dictionary:
	return {"role": role}
