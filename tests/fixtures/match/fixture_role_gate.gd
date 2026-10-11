class_name FixtureRoleGate
extends Condition
## A condition that gates on the actor's role (as ActorRole will) and always passes, so a test
## sees ModeCheck's role-reveal warnings (§9.2) on a role-gated rule without a role check.


func gates_on_role() -> bool:
	return true


func _test(_ctx: MatchContext) -> bool:
	return true
