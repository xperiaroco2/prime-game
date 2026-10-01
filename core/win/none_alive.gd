class_name NoneAlive
extends Condition
## Passes when no player of `side` is present any more (ARCHITECTURE §3.4, §9.4): each player whose
## role belongs to the side has left. A downed or dead player is still present, and still counts:
## killing takes time from the crew (death is a delay, they respawn), and every crew member down at
## once must not end the round (vision revision 1). A player without a role of the mode belongs to
## no side. With no player of the side at all it holds, as its words say; the base mode's deal
## always leaves at least one crew member (DealRoles, `leave_at_least`), so there it cannot hold
## at the start of a round.
##
## It reads every player's role, which is hidden (§5), but only inside a win condition: those
## check facts and reject nothing, and `won` reaches no peer (§9.2); MatchEnded names only the
## side. The dissidents' "no crew present". The class keeps its name from the "no crew alive" it
## replaced (M4-2), so the content API's part list and the data that names it stay as they were.

## A SideSpec id of the mode.
@export var side: StringName


static func of(side_id: StringName) -> NoneAlive:
	var condition := NoneAlive.new()
	condition.side = side_id
	return condition


func _test(ctx: MatchContext) -> bool:
	for peer: int in ctx.state.peers():
		var player := ctx.state.players[peer]
		if not player.is_present():
			continue
		var role := ctx.mode.find_role(player.role)
		if role != null and role.side == side:
			return false
	return true


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if side.is_empty():
		found.append("NoneAlive has no side")
	elif mode.find_side(side) == null:
		found.append("NoneAlive names side %s, which the mode does not declare" % side)
	return found
