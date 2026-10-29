class_name SwappedEvent
extends MatchEvent
## Another of a player's three places came into its hand (ARCHITECTURE §4.2, §7.1; GDD §6
## "Drawing from the belt"): a `Draw` (keys 1, 2, 3, the wheel) or a `Swap` (X: back to the place
## held last). `place` is the new selected place, 0..2; the old hand item stays in its place, now
## on the belt, and an empty place is an empty hand. A two-handed hand item put down first has its
## own ItemPlaced (`put_down`) before this event. Who carries what, and where, is public, as the
## avatar's hand and belt items are. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
var place: int


func _init(by_peer: int, selected_place: int = 0) -> void:
	peer = by_peer
	place = selected_place


func event_name() -> StringName:
	return &"Swapped"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "place": place}
