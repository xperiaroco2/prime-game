class_name StepInteract
extends ScenarioStep
## Sends Interact naming `station` (a station by kind and index, ScenarioTarget STATION), or naming
## `item` instead (an item that is a source, such as Cooking's boxes: the nearest of its kind,
## ScenarioTarget NEAREST; #1209). Done when the event `until` names arrives for this bot (an
## event with no peer counts for any bot), or with `expect_rejected` when that Rejected arrives. The
## intent carries no facing: the host checks reach and sight from the bot's position, so walk there
## first.
## (ARCHITECTURE §9.7, #796)

@export var station: ScenarioTarget
## The item the Interact names in place of a station; null names the station.
@export var item: ScenarioTarget
## The event that marks the use applied: the station kind's task type emits it (use_emits()), or
## the item's take (ItemPickedUp). No default: a use's events are the type's own.
@export var until: StringName


func step_name() -> StringName:
	return &"Interact"


func sends_intent() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := super()
	if item != null:
		found.append_array(target_problems(item, "item"))
		if station != null:
			found.append("an Interact names a station or an item, not both")
		if item.kind != ScenarioTarget.Kind.NEAREST:
			found.append("an Interact's item is the nearest of a kind: nearest(item_kind)")
	else:
		found.append_array(target_problems(station, "station"))
		if station != null and station.kind != ScenarioTarget.Kind.STATION:
			found.append("an Interact names a station: station(kind, i)")
	if until.is_empty() and expect_rejected.is_empty():
		found.append("no until: name the event the use emits")
	return found
