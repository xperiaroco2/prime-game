class_name StepSetColour
extends FixtureIntentStep
## Sends SetProfile asking for body colour `colour` with an empty name, so the host keeps the bot's
## own (JoinRules.set_profile: a name with nothing usable keeps the current one): done when a
## ProfileChanged with that colour arrives (a scenario gives each bot its own colour: `peer` is a
## bot number in a step's fields, and done_fields gets a peer id), or with `expect_rejected` when
## that Rejected arrives (`not_at_mirror` away from the mirror). (ARCHITECTURE §7.1.24, §9.7, #1394)
##
## A test step beside the fixture scenario that uses it (mirror_two_colours.tres), as the
## pinball's StepFlippers (#1510).

@export var colour := 0


func step_name() -> StringName:
	return &"SetColour"


func intent_kind() -> StringName:
	return Intents.SET_PROFILE


func intent_args() -> Dictionary:
	return {"name": "", "colour": colour}


func done_event() -> StringName:
	return &"ProfileChanged"


func done_fields(_peer: int) -> Dictionary:
	return {"colour": colour}
