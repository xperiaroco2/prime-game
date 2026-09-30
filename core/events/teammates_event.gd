class_name TeammatesEvent
extends MatchEvent
## The players of a role that knows its teammates (the dissidents), dealt by DealRoles
## (ARCHITECTURE §3.3, §4.2): the role and every one of its players, the recipient included.
## Audience: every present player of that role, evaluated at emission (§5), and nobody else.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ROLE

## A GameRole id of the mode.
var role: StringName
## The role's players, in peer-id order.
var peers: PackedInt32Array


func _init(role_id: StringName, role_peers: PackedInt32Array) -> void:
	role = role_id
	peers = role_peers.duplicate()


func event_name() -> StringName:
	return &"Teammates"


func audience() -> Audience:
	return Audience.of_role(role)


func to_dict() -> Dictionary:
	return {"role": role, "peers": peers.duplicate()}
