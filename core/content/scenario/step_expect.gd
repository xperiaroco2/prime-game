class_name StepExpect
extends ScenarioStep
## Checks that the bot received a matching event since its previous step started, or does
## within `within_s` seconds. (ARCHITECTURE §9.7)

@export var event: StringName = &""
## Fields the event must match; a field naming a player holds the bot's number.
@export var fields := {}
@export var within_s := 0.0


func step_name() -> StringName:
	return &"Expect"


func problems() -> PackedStringArray:
	var found := super()
	if event.is_empty():
		found.append("no event")
	return found
