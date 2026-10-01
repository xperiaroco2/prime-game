class_name TickSystem
extends ContentPart
## What runs every tick of a phase, in the order the phase spec lists (ARCHITECTURE §3.3, §9.4):
## after the phase's own timers and before the match clock. The base mode's Round has TaskTicks
## (2f); the other phases have none.


func run(_ctx: MatchContext) -> void:
	pass


## The event classes this system can emit (§9.2).
func emits() -> Array[Script]:
	return []


## What this system needs of the map its phase plays on, as RuleEffect.add_demands (§9.4): the
## layout check and the lobby's fit check add it to the rows' demands, taking per tag the most of
## any one phase on that level (a system in two phases needs its markers once). LifeTicks forwards
## its Respawn's. No demand by default.
func add_demands(_settings: Dictionary[StringName, int], _players: int, _into: Demands) -> void:
	pass


## The outcomes run() can report through MatchContext.report_outcome: ModeCheck requires a row
## for each from the phases that list this system (§9.1).
func reported_outcomes() -> Array[StringName]:
	return []
