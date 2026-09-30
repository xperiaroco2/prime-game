class_name FixtureCost
extends Cost
## A use limit: passes while the actor paid `key` fewer than `limit` times; paying counts one.
## Rejects with `used_up`.

@export var key: StringName = &"uses"
@export var limit := 1


static func of(counter_key: StringName, uses: int) -> FixtureCost:
	var cost := FixtureCost.new()
	cost.key = counter_key
	cost.limit = uses
	return cost


func pay(ctx: MatchContext) -> void:
	ctx.state.add_to_counter(ctx.actor, key, 1)


func _test(ctx: MatchContext) -> bool:
	return ctx.state.counter(ctx.actor, key) < limit


func _reason() -> StringName:
	return &"used_up"
