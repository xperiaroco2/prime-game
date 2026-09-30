class_name FixtureSpawnItem
extends RuleEffect
## Stands in for a deal's spawn (SpawnItems 2c, Delivery 2f) in tests: a transition action that
## puts an item of `kind` at `at` into the match state, then raises item_rested (spawn) through
## Items.raise_rested.

@export var kind: ItemKind
@export var at := Vector3.ZERO


func run(ctx: MatchContext) -> void:
	Items.raise_rested(ctx, ctx.state.add_item(kind, at), Items.SPAWN)
