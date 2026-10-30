class_name StepTakeOffer
extends ScenarioStep
## Waits until the player `target` names (a `bot(i)` target) offers the bot its hand item (an open
## OfferMade to the bot's player), then sends TakeOffer of that giver: the bot takes the item into
## its own hand (#1434). Done when an ItemPickedUp arrives whose `peer` is the bot's own, so an
## item that lands with anyone else never counts. (ARCHITECTURE §9.7)

@export var target: ScenarioTarget


func step_name() -> StringName:
	return &"TakeOffer"


func sends_intent() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := super()
	found.append_array(target_problems(target, "target"))
	if target != null and target.kind != ScenarioTarget.Kind.BOT:
		found.append("a TakeOffer targets a player: bot(i)")
	return found
