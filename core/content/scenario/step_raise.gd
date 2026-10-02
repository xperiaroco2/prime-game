class_name StepRaise
extends ScenarioStep
## Sends Raise of the player `target` names (a `bot(i)` target) and holds it for `hold_s` seconds
## from the step's start. Done when its RaiseStarted has arrived and `hold_s` has passed, or the
## raise ended before (its RaiseStopped, or a Revived of the target). The bot still holds E after
## the step: a StopRaise step lets go. (ARCHITECTURE §9.7; M4-4)

@export var target: ScenarioTarget
## Seconds from the step's start, 0 to 600: 0 is done as soon as the raise started.
@export var hold_s := 0.0


func step_name() -> StringName:
	return &"Raise"


func sends_intent() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := super()
	found.append_array(target_problems(target, "target"))
	if target != null and target.kind != ScenarioTarget.Kind.BOT:
		found.append("a Raise targets a player: bot(i)")
	if hold_s < 0.0 or hold_s > 600.0:
		found.append("hold_s %s is outside 0 to 600" % hold_s)
	return found
