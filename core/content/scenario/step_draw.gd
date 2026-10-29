class_name StepDraw
extends ScenarioStep
## Sends Draw of `place`: that belt place comes into the bot's hand (GDD §6 "Drawing from the belt",
## #1218). Done when its own Swapped of that place arrives. (ARCHITECTURE §9.7)

## The place drawn: 0, 1 or 2 (the keys 1, 2 and 3). Any int is sent as it is, so a refusal step
## can name a place the host refuses (`no_such_place`).
@export var place := 0


func step_name() -> StringName:
	return &"Draw"


func sends_intent() -> bool:
	return true
