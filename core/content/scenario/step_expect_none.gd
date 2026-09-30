class_name StepExpectNone
extends ScenarioStep
## Checks that no matching event arrives for `for_s` seconds; the first one fails the step.
## (ARCHITECTURE §9.7)

@export var event: StringName = &""
## Fields the event must match; a field naming a player holds the bot's number.
@export var fields := {}
@export var for_s := 0.0


func step_name() -> StringName:
	return &"ExpectNone"


func problems() -> PackedStringArray:
	var found := super()
	if event.is_empty():
		found.append("no event")
	return found
