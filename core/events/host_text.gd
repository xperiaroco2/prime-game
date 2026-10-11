class_name HostText
extends RefCounted
## Text the host makes for players, as an id plus arguments (ARCHITECTURE §4.2, #548): never a
## sentence, so each client shows it in its own language. The client owns the table from the id
## to a key of the UI copy deck (HostTextView); the wire carries only wire ids and whole numbers.
## SettingsChanged's shortfalls are HostTexts; the ids below are those FitCheck and Demands make.

## Fewer players than the mode's minimum. numbers: count (how many more), min, max.
const PLAYERS_FEW := &"players_few"
## More players than the mode's maximum. numbers: count (how many too many), min, max.
const PLAYERS_MANY := &"players_many"
## A spawn tag with fewer markers on the map than the match needs. ids: [the tag]; numbers: need,
## have.
const MARKERS := &"markers"
## A station kind whose palette has fewer colours than the match needs. ids: [the station kind];
## numbers: need, have.
const COLOURS := &"colours"
## The chosen map has no layout. No arguments: SettingsChanged names the map.
const NO_LAYOUT := &"no_layout"

## What the text says (a wire id).
var id: StringName
## Its subjects (wire ids: a spawn tag, a station kind), in order.
var ids := PackedStringArray()
## Its whole-number arguments, by name (wire ids: `count`, `need`, ...).
var numbers: Dictionary[StringName, int] = {}


static func of(
	text_id: StringName,
	subjects := PackedStringArray(),
	arguments: Dictionary[StringName, int] = {}
) -> HostText:
	var text := HostText.new()
	text.id = text_id
	text.ids = subjects.duplicate()
	text.numbers = arguments.duplicate()
	return text


## The HostTexts as the event's to_dict() holds them (and the client decodes them).
static func to_dicts(texts: Array[HostText]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for text: HostText in texts:
		found.append(text.to_dict())
	return found


func to_dict() -> Dictionary:
	return {"id": id, "ids": ids.duplicate(), "numbers": numbers.duplicate()}


## For test failure messages only, never a player's screen.
func _to_string() -> String:
	return "%s%s%s" % [id, ids, numbers]
