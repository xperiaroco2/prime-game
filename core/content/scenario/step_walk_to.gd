class_name StepWalkTo
extends ScenarioStep
## Sends honest MoveClaims straight towards the target at walk or sprint speed (at the crawl
## speed, never sprinting, while downed; a dead bot cannot walk and fails the step); a level with
## walls needs waypoints. Done when it is within `stop_m` of the target horizontally: 1 m
## before a circle, the put-down distance, to deliver. (ARCHITECTURE §9.7)

@export var target: ScenarioTarget
@export var sprint := false
@export var stop_m := 0.5


func step_name() -> StringName:
	return &"WalkTo"


func problems() -> PackedStringArray:
	var found := super()
	found.append_array(target_problems(target, "target"))
	if stop_m < 0.0:
		found.append("stop_m is negative")
	return found
