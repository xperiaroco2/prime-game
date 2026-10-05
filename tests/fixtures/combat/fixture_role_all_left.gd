class_name FixtureRoleAllLeft
extends Condition
## Stands in for NoneAlive ("no crew present", M4-2) in tests of the life rule: passes when some
## player has the role `role` and none of them is present any more (each has left). Unlike
## NoneAlive it does not hold before the roles are set, so a fixture round is not won on entry.

@export var role: StringName = &"crew"


static func of(role_id: StringName) -> FixtureRoleAllLeft:
	var condition := FixtureRoleAllLeft.new()
	condition.role = role_id
	return condition


## It reads every player of the role, not the actor: a win condition holds it.
func reads_actor_state() -> bool:
	return false


func _test(ctx: MatchContext) -> bool:
	var found := false
	for peer: int in ctx.state.peers():
		var player := ctx.state.players[peer]
		if player.role != role:
			continue
		found = true
		if player.is_present():
			return false
	return found
