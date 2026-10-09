class_name FixtureReport
extends RuleEffect
## Reports the outcome `outcome` with the argument "from a rule", as ReportOutcome does (#599).

@export var outcome: StringName = &"go"


static func of(outcome_name: StringName) -> FixtureReport:
	var effect := FixtureReport.new()
	effect.outcome = outcome_name
	return effect


func run(ctx: MatchContext) -> void:
	ctx.report_outcome(outcome, "from a rule")


func reported_outcomes() -> Array[StringName]:
	return [outcome]
