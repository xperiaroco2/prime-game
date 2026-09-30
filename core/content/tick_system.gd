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
