class_name FixtureNoteEvent
extends MatchEvent
## A test event with a text and a chosen audience, so tests can see the order in which parts ran.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var text: String
var _audience: Audience


func _init(note: String, to: Audience = null) -> void:
	text = note
	_audience = to if to != null else Audience.everyone()


func event_name() -> StringName:
	return &"FixtureNote"


func audience() -> Audience:
	return _audience


func to_dict() -> Dictionary:
	return {"text": text}
