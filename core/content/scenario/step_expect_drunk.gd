class_name StepExpectDrunk
extends ScenarioStep
## Checks a player's drunk value (the bar, GDD §3; ARCHITECTURE §7.1.20) as this bot sees it:
## done once it lies within `at_least` to `at_most`, now or within `within_s` seconds; fails
## after. `bot` 0 is this bot itself, read from its own SelfStatus (the snapshot leaves the own
## avatar out); another bot's number reads that bot's avatar in this bot's last snapshot.
## (ARCHITECTURE §9.7)

@export var bot := 0
@export var at_least := 0
@export var at_most := 255
@export var within_s := 0.0


func step_name() -> StringName:
	return &"ExpectDrunk"


func problems() -> PackedStringArray:
	var found := super()
	if bot < 0:
		found.append("bot %d is below 0" % bot)
	if at_least < 0 or at_most > 255 or at_least > at_most:
		found.append("at_least %d to at_most %d is no range within 0 to 255" % [at_least, at_most])
	if within_s < 0.0:
		found.append("within_s is negative")
	return found
