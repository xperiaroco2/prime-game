class_name FixtureRaise
extends RuleEffect
## Raises the fact `fact`.

@export var fact: StringName = Facts.ITEM_RESTED


static func of(fact_name: StringName) -> FixtureRaise:
	var effect := FixtureRaise.new()
	effect.fact = fact_name
	return effect


func run(ctx: MatchContext) -> void:
	ctx.raise_fact(Fact.new(fact))
