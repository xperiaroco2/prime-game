class_name SetFlippers
extends RuleEffect
## The seated player's flippers become the Flippers intent's `left` and `right`
## (Pinball.set_flippers; ARCHITECTURE §7.1.22, §9.4; #1398): one PinballState when either changed,
## none when both are as they were. Only in a rule on Flippers that holds PinballSeated (check()). A
## `left` or `right` that is missing or no bool is refused `bad_args` (refusal()).
##
## Emits: PinballState (everyone). No demands.


func run(ctx: MatchContext) -> void:
	Pinball.set_flippers(ctx, ctx.command.get_bool("left"), ctx.command.get_bool("right"))


func refusal(ctx: MatchContext) -> StringName:
	if ctx.command == null:
		return RejectReasons.BAD_ARGS
	if not (ctx.command.field("left") is bool and ctx.command.field("right") is bool):
		return RejectReasons.BAD_ARGS
	return &""


func emits() -> Array[Script]:
	return [PinballStateEvent]


## Where it sits: only in a rule on Flippers, which holds a PinballSeated that is not negated.
func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	for rule: Rule in Pinball.rules_holding(mode, self):
		if rule.trigger != Intents.FLIPPERS:
			found.append("SetFlippers is only for a rule on Flippers, not %s" % rule.trigger)
		elif not Pinball.holds_condition(rule, PinballSeated):
			found.append("the rule on Flippers sets the flippers but holds no PinballSeated")
	return found
