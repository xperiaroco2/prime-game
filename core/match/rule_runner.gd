class_name RuleRunner
extends RefCounted
## Runs one rule (ARCHITECTURE §9.2): every condition and cost is checked in order, and the first
## that fails stops the rule with its reason; then every cost is paid in order; then the effects
## run in order. So a refused intent pays nothing.


## Runs `rule` in `ctx`. Returns the rejection reason of the first failing condition, or an empty
## name when the rule applied. The caller rejects an intent with the reason; for a fact a failure
## means nothing happens.
static func run(rule: Rule, ctx: MatchContext) -> StringName:
	for condition: Condition in rule.conditions:
		if not condition.passes(ctx):
			return condition.rejection_reason()
	for cost: Cost in rule.costs():
		cost.pay(ctx)
	for effect: RuleEffect in rule.effects:
		effect.run(ctx)
	return &""
