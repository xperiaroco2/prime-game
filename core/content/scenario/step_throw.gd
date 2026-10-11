class_name StepThrow
extends ScenarioStep
## Faces `towards`, tilts that facing up by `pitch_deg` and sends Throw. Done when the ItemThrown
## of the item it held arrives. (ARCHITECTURE §9.7; throwing ADR, 37d)

@export var towards: ScenarioTarget
## Degrees above the horizontal, -90 to 90: 0 throws flat, 90 straight up, -90 straight down.
@export var pitch_deg := 0.0


func step_name() -> StringName:
	return &"Throw"


func sends_intent() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := super()
	found.append_array(target_problems(towards, "towards"))
	if not (pitch_deg >= -90.0 and pitch_deg <= 90.0):
		found.append("pitch_deg %s is outside -90 to 90" % pitch_deg)
	return found
