class_name StepLoadAck
extends ScenarioStep
## Answers the next LoadMatch: with `skip`, never, so the loading deadline drops the bot.
## Done when the ack is sent, or skipped. (ARCHITECTURE §9.7)

@export var skip := false


func step_name() -> StringName:
	return &"LoadAck"
