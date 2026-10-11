class_name EventSeen
extends TutorialTrigger
## Trigger: the own session decoded `event` with `fields` (docs/design/tutorial.md §3), a subset
## of its payload matched as a bot scenario's WaitFor (§9.7). A field's value is matched as it is,
## except three markers: OWN (the own peer) and OTHER (any other peer) on a peer field, HELD (the
## item the own hand held as the step started) on an item field.

## The own peer.
const OWN := &"own"
## Any peer but the own.
const OTHER := &"other"
## The item in the own hand as the step started.
const HELD := &"held"

## The event's name (`ItemPickedUp`).
@export var event: StringName = &""
## Field name -> the value it must hold, or a marker.
@export var fields := {}


func part_name() -> StringName:
	return &"EventSeen"


func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if event.is_empty():
		found.append("EventSeen: no event")
	for key: Variant in fields:
		if not (key is String or key is StringName):
			found.append("EventSeen %s: field %s is not a name" % [event, key])
	return found
