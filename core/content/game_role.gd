class_name GameRole
extends ContentPart
## A role (ARCHITECTURE §9.3; named GameRole because a global `Role` would shadow
## NetTransport.Role): the side it wins with, whether its players learn each other
## (Teammates, 2c), and its abilities, which apply to its players only (§9.2). A player's role
## never leaves the host except to that player, and to teammates of a role that knows them (§5).

@export var id: StringName
@export var display_name: String
## A SideSpec id of the mode.
@export var side: StringName
@export var knows_teammates := false
## Rules on intents; a role's `Use` fires only when the held item has no `Use` rule (§9.2).
@export var actions: Array[Rule] = []


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("a role has no id")
	if mode.find_side(side) == null:
		found.append("role %s names side %s, which the mode does not declare" % [id, side])
	return found
