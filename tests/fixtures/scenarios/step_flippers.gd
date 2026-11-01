class_name StepFlippers
extends ScenarioStep
## Sends Flippers(left, right), the held state of the pinball's two flippers (Intents.FLIPPERS,
## §7.1.22): done when a PinballState arrives with this bot's player seated and both flippers as
## the step holds them, or with `expect_rejected` when that Rejected arrives. The state must change
## (an unchanged Flippers emits no PinballState), so a script alternates. (ARCHITECTURE §9.7, #1510)
##
## A test step, not a content step: it lives beside the fixture scenario that uses it
## (pinball_plays_a_ball.tres) rather than in core/content/scenario/ with the closed list, as the
## re-scope of #1510 settles (the new scenario and its flipper step in tests/fixtures/scenarios/);
## a shipped scenario in content/scenarios/ does not use it.

@export var left := false
@export var right := false


func step_name() -> StringName:
	return &"Flippers"


func sends_intent() -> bool:
	return true
