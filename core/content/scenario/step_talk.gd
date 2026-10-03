class_name StepTalk
extends ScenarioStep
## Turns the bot's synthetic voice on or off: from this step on it talks as the scenario's `voice`
## says (`talking`), or sends no frame (ARCHITECTURE §9.7, §4.6). A bot talks from its join until a
## Talk step turns it off. Done at once. The core runner has no voice: it only records the choice.

@export var talking := true


func step_name() -> StringName:
	return &"Talk"
