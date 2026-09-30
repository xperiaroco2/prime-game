class_name FixtureBump
extends RuleEffect
## Adds `amount` (or the match setting `count_setting`) to peer 0's counter `key`.

@export var key: StringName = &"win"
@export var count_setting: StringName
@export var amount := 1


static func of(counter_key: StringName, by: int = 1) -> FixtureBump:
	var effect := FixtureBump.new()
	effect.key = counter_key
	effect.amount = by
	return effect


func run(ctx: MatchContext) -> void:
	var by := amount if count_setting.is_empty() else ctx.setting(count_setting)
	ctx.state.add_to_counter(0, key, by)
