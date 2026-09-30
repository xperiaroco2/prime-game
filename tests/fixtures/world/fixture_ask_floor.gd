class_name FixtureAskFloor
extends RuleEffect
## A transition action that asks the world for the floor below the origin, so a test sees which
## level a row's actions ask about (ARCHITECTURE §4.5, E9).


func run(ctx: MatchContext) -> void:
	ctx.world.floor_below(Vector3.UP)
