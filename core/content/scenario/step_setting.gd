class_name StepSetting
extends ScenarioStep
## The host's bot sends ChangeSettings with one whole-number setting. Done when
## SettingsChanged arrives. (ARCHITECTURE §9.7)

@export var id: StringName = &""
@export var value := 0


func step_name() -> StringName:
	return &"Setting"


func sends_intent() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := super()
	if id.is_empty():
		found.append("no setting id")
	return found
