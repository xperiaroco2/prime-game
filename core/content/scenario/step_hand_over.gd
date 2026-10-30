class_name StepHandOver
extends ScenarioStep
## Sends HandOver of the player `target` names (a `bot(i)` target): the bot offers its hand item to
## that player (#1389, #1434). Done when the OfferMade of the bot to that player arrives; the item
## leaves the hand only when the receiver takes it (StepTakeOffer), so a step that needs the empty
## hand waits for that ItemPickedUp first. (ARCHITECTURE §9.7)

@export var target: ScenarioTarget


func step_name() -> StringName:
	return &"HandOver"


func sends_intent() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := super()
	found.append_array(target_problems(target, "target"))
	if target != null and target.kind != ScenarioTarget.Kind.BOT:
		found.append("a HandOver targets a player: bot(i)")
	return found
