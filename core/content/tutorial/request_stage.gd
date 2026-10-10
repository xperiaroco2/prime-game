class_name RequestStage
extends TutorialAction
## Action: the client sends NextStage, so the host stages the lesson (docs/design/tutorial.md §2.4,
## §3; E65). No settings.


func part_name() -> StringName:
	return &"RequestStage"
