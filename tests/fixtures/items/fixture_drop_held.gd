class_name FixtureDropHeld
extends RuleEffect
## Stands in for the life rule (2g) in tests: the actor dies (`death`) or leaves (`leave`), then
## its held item drops through Items.drop_held, in that order, as §3.4 and §9.2 require.

@export var cause := Items.DEATH


static func of(why: StringName) -> FixtureDropHeld:
	var effect := FixtureDropHeld.new()
	effect.cause = why
	return effect


func run(ctx: MatchContext) -> void:
	var player := ctx.actor_state()
	player.life = PlayerState.Life.LEFT if cause == Items.LEAVE else PlayerState.Life.GHOST
	Items.drop_held(ctx, ctx.actor, cause)


func emits() -> Array[Script]:
	return [ItemPlacedEvent]
