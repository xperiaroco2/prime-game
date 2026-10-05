class_name FixtureCounterAtLeast
extends Condition
## Passes when peer 0's counter `key` is at least `at_least`; rejects with `reason`.

@export var key: StringName = &"win"
@export var at_least := 1
@export var reason: StringName = &"fixture_no"


static func of(counter_key: StringName, why: StringName = &"fixture_no") -> FixtureCounterAtLeast:
	var condition := FixtureCounterAtLeast.new()
	condition.key = counter_key
	condition.reason = why
	return condition


## It reads peer 0's counter, not the actor: the fixture mode's win conditions hold it.
func reads_actor_state() -> bool:
	return false


func _test(ctx: MatchContext) -> bool:
	return ctx.state.counter(0, key) >= at_least


func _reason() -> StringName:
	return reason
