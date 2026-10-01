class_name NoneAlive
extends Condition
## Passes when no player of `side` is alive (ARCHITECTURE §3.4, §9.4): each player whose role
## belongs to the side is downed or dead, or has left (a leave counts as dead for the win
## conditions, §3.5). A player without a role of the mode belongs to no side. With no player of
## the side at all it holds, as its words say; the base mode's deal always leaves at least one
## crew member (DealRoles, `leave_at_least`), so there it cannot hold at the start of a round.
##
## It reads every player's role, which is hidden (§5), but only inside a win condition: those
## check facts and reject nothing, and `won` reaches no peer (§9.2); MatchEnded names only the
## side. The dissidents' "no crew alive".

## A SideSpec id of the mode.
@export var side: StringName


static func of(side_id: StringName) -> NoneAlive:
	var condition := NoneAlive.new()
	condition.side = side_id
	return condition


func _test(ctx: MatchContext) -> bool:
	for peer: int in ctx.state.peers():
		var player := ctx.state.players[peer]
		if not player.is_alive():
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
