class_name StepJoin
extends ScenarioStep
## Sends Hello `at_s` seconds after the start instead of at once: a late join that cancels
## the countdown, or one refused in Loading. Done when its Welcome arrives. As a bot's first step it
## joins once, and a refusal fails it at once. Directly after the bot's own Leave it joins again
## (P12 (a) of the returning-players ADR): on a peer id new to the session, and a `joins_closed` or
## a refused connection is tried again every 0.5 s until `deadline_s`, then fails naming the last
## reason (P12 (t2)). (ARCHITECTURE §9.7)

## Seconds after the start.
@export var at_s := 0.0
## Seconds after the start until which a Join after the bot's own Leave tries again; above
## `at_s` there, 0 on a first Join (BotScenario.problems()).
@export var deadline_s := 0.0


func step_name() -> StringName:
	return &"Join"


func sends_intent() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := super()
	if at_s < 0.0:
		found.append("at_s is negative")
	return found
