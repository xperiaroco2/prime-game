class_name RuleEffect
extends ContentPart
## An effect, "what happens" (ARCHITECTURE §9.2; named RuleEffect because a global `Effect`
## would shadow GdUnit4's GdUnitMessageWriter.Effect): run in order after a rule's conditions and
## costs passed, or as a transition action with no actor (§9.4). An effect changes MatchState only
## through core/'s own rules, emits events (whose class decides the audience, never the effect),
## raises facts, and may report an outcome of the current phase.


func run(_ctx: MatchContext) -> void:
	pass


## The event classes this effect can emit, so a review of the part shows what it reveals, and
## ModeCheck can warn when a role-owned rule emits to everyone (§9.2).
func emits() -> Array[Script]:
	return []


## The outcomes this effect can report (ReportOutcome, #599); each needs a transition row.
func reported_outcomes() -> Array[StringName]:
	return []


## What this effect needs of the map, given the match settings and the player count: markers per
## spawn tag and, for a station kind, colours (§9.4). The lobby's fit check sums them over
## every row into a phase on the map. No demand by default.
func add_demands(_settings: Dictionary[StringName, int], _players: int, _into: Demands) -> void:
	pass


## Whether the match settings together break this transition action's rule: the rejection
## reason, or empty when they are fine. The lobby's ChangeSettings asks every row's actions with
## the settings as they would be, before applying any (§4.1), so a combination this action cannot
## deal is refused whole. DealTasks: `tasks` above the task types left after the bans, or every
## task type banned (`out_of_bounds`, #79). Fine by default.
func settings_problem(
	_settings: Dictionary[StringName, int],
	_id_sets: Dictionary[StringName, PackedStringArray],
	_mode: GameMode
) -> StringName:
	return &""
