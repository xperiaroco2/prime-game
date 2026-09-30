class_name FixtureRoleAllDead
extends Condition
## Stands in for 2h's NoneAlive in tests of the life rule: passes when some player has the role
## `role` and none of them is alive (each is a ghost or has left). Unlike NoneAlive it does not hold
## before the roles are set, so a fixture round is not won on entry.

@export var role: StringName = &"crew"


static func of(role_id: StringName) -> FixtureRoleAllDead:
	var condition := FixtureRoleAllDead.new()
	condition.role = role_id
	return condition


func _test(ctx: MatchContext) -> bool:
	var found := false
	for peer: int in ctx.state.peers():
		var player := ctx.state.players[peer]
		if player.role != role:
			continue
		found = true
		if player.is_alive():
			return false
	return found
