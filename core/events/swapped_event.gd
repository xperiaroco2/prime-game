class_name SwappedEvent
extends MatchEvent
## A player swapped its hand and belt items (ARCHITECTURE §4.2, §7.1; vision revision 1, Two
## hands): `Swap`. Either slot may have been empty. Who carries what, and where, is public, as the
## avatar's hand and belt items are. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int


func _init(by_peer: int) -> void:
	peer = by_peer


func event_name() -> StringName:
	return &"Swapped"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer}
