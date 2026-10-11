class_name RoleFacts
extends RefCounted
## What the Esc menu's Role tab shows (#491, #175's update of 2026-10-03; prime-game-ui handoff s05
## `role-*` at ui-0.4.0), from the own ClientModel and the client's own mode only: the own role, its
## goal and, for a role whose Teammates the own client holds (a dissident's), the teammates' names.
## It reads model.role, model.teammates of that role, own_peer and the roster's names, nothing else:
## per-peer filtering (invariant 2) decides what the model holds.

## The copy deck's goal of each role the base mode has, by role id; a role not named here shows no
## goal line.
const GOAL_KEYS: Dictionary[StringName, String] = {
	&"crew": "role.goal.engineer",
	&"dissident": "role.goal.dissident",
}

## The own role's deck key (its display name when the deck has none); "" before RoleAssigned.
var role_key := ""
## Its goal's deck key; "" for none.
var goal_key := ""
## The teammates' names in join order (ascending peer id), the own player not among them; a
## teammate who left the session (gone from the roster) is skipped.
var team := PackedStringArray()


static func of(model: ClientModel, mode: GameMode) -> RoleFacts:
	var facts := RoleFacts.new()
	if model == null or model.role.is_empty():
		return facts
	facts.role_key = ContentNames.role(model.role, mode)
	facts.goal_key = str(GOAL_KEYS.get(model.role, ""))
	var peers: Array[int] = []
	for peer: int in model.teammates.get(model.role, PackedInt32Array()):
		if peer != model.own_peer and model.roster.has(peer) and not peers.has(peer):
			peers.append(peer)
	peers.sort()
	for peer: int in peers:
		facts.team.append(model.roster[peer].name)
	return facts
