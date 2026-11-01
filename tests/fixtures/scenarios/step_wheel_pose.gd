class_name StepWheelPose
extends FixtureIntentStep
## Sends WheelPose(legs, arms), the pose wheel's whole pose (Intents.WHEEL_POSE, §7.1.23): done
## when a SelfStatus arrives with this bot's wheel_pose byte as the pick encodes it (WheelPoseCode;
## the player's own client learns its own pose only there), or with `expect_rejected` when that
## Rejected arrives. A Jump step ends the pose again (an own move). (#1509)
##
## A test step, not a content step: it lives beside the fixture scenario that uses it
## (wheel_pose_in_the_lobby.tres), as StepFlippers does.

## Indices into the mode's WheelPoses, one of each (the base mode's: legs 0 to 5, arms 0 to 7).
@export var legs := 0
@export var arms := 0


func step_name() -> StringName:
	return &"WheelPose"


func intent_kind() -> StringName:
	return Intents.WHEEL_POSE


func intent_args() -> Dictionary:
	return {"legs": legs, "arms": arms}


func done_event() -> StringName:
	return &"SelfStatus"


func done_fields(_peer: int) -> Dictionary:
	return {"wheel_pose": WheelPoseCode.encode(legs, arms)}
