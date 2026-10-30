class_name StepHandOver
extends ScenarioStep
## Sends HandOver of the player `target` names (a `bot(i)` target): the bot hands its hand item to
## that player (#1389). Done when an ItemPickedUp arrives whose `peer` is the target's and whose
## `item` is the one that left the bot's hand, so an item that lands with anyone else, or comes
## back, never counts. (ARCHITECTURE §9.7)

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
