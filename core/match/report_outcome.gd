class_name ReportOutcome
extends RuleEffect
## Reports `outcome` in the current phase (ARCHITECTURE §3.1, §9.2, §9.4.2), with `argument` as
## the outcome's argument (none when empty), which the row's actions read as
## MatchContext.outcome_argument. The phase must have a row for `outcome`: ModeCheck finds the
## outcomes the rules of accepted intents can report (reported_outcomes) and requires a row for
## each. The first outcome of a step wins; a later one is dropped and its sender gets
## `outcome_dropped` (§3.1). Run as a transition action, it is a row error (Match.report_outcome).
## The tutorial's NextStage rule reports `next` with it (#599, docs/design/tutorial.md §2.4).
##
## Emits nothing: an outcome reaches no peer (§9.2); the row it moves the match along does.

@export var outcome: StringName = &""
## The outcome's argument: a side for EndMatch, say. Empty: none (null). Unused by the tutorial.
@export var argument: StringName = &""


func run(ctx: MatchContext) -> void:
	var value: Variant = null
	if not argument.is_empty():
		value = argument
	ctx.report_outcome(outcome, value)


func reported_outcomes() -> Array[StringName]:
	return [outcome]


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if outcome.is_empty():
		found.append("ReportOutcome names no outcome")
	return found
