class_name UsePinball
extends RuleEffect
## The actor's Interact at the pinball machine (ARCHITECTURE §7.1.22, §9.4; #1398; GDD §3 "The
## pinball"): with the seat free it takes the seat and a game of `balls` balls starts with
## `targets`' points (Pinball.start); the seated player's own Interact gives the seat up and ends
## the game (Pinball.end, the score counting for the best). Only in a station kind's rule on
## Interact, after the conditions required_conditions() lists (PinballUsable refuses a second
## player `unavailable`); where it is, PinballTicks is (check(): PinballTicks.problems).
##
## Emits: PinballState (everyone). No demands.

## The balls of a game (provisional, not a decision: the numbers come on the hall greybox).
@export var balls := 0
## The table's targets and their points (provisional, not a decision).
@export var targets: Array[PinballTarget] = []


func run(ctx: MatchContext) -> void:
	if Pinball.seated(ctx.state) == ctx.actor:
		Pinball.end(ctx)
		return
	var station := Stations.target_of(ctx)
	Pinball.start(ctx, station.id if station != null else -1, balls, targets)


## The condition classes a rule holding this effect must hold, not negated (check()): the actor at
## the machine and seeing it, and the seat free or its own.
static func required_conditions() -> Array[Script]:
	return [AtStation, StationInSight, PinballUsable]


func emits() -> Array[Script]:
	return [PinballStateEvent]


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(found, [out_of_bounds("balls", balls, 1, 9)])
	if targets.is_empty():
		found.append("UsePinball needs at least one target")
	var ids: Dictionary[StringName, bool] = {}
	for target: PinballTarget in targets:
		if target == null:
			found.append("UsePinball has an empty target")
		elif ids.has(target.id):
			found.append("UsePinball has two targets of id %s" % target.id)
		else:
			ids[target.id] = true
	var kinds_rules: Array[Rule] = []
	for kind: StationKind in Stations.kinds_in(mode):
		kinds_rules.append_array(kind.actions)
	for rule: Rule in Pinball.rules_holding(mode, self):
		if rule.trigger != Intents.INTERACT or not kinds_rules.has(rule):
			found.append(
				"UsePinball is only for a station kind's rule on Interact, not %s" % rule.trigger
			)
			continue
		for required: Script in required_conditions():
			if not Pinball.holds_condition(rule, required):
				found.append(
					(
						"the pinball's rule uses the machine, which requires the condition %s"
						% required.get_global_name()
					)
				)
	found.append_array(PinballTicks.problems(mode))
	return found
