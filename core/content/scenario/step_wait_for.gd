class_name StepWaitFor
extends ScenarioStep
## Waits until the bot receives a matching event. (ARCHITECTURE §9.7)

@export var event: StringName = &""
## Fields the event must match; a field naming a player holds the bot's number.
@export var fields := {}


func step_name() -> StringName:
	return &"WaitFor"


func problems() -> PackedStringArray:
	var found := super()
	if event.is_empty():
		found.append("no event")
	return found
