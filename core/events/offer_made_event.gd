class_name OfferMadeEvent
extends MatchEvent
## A living player holds its hand item out to another (ARCHITECTURE §4.2, §7.1; #1434): `giver`
## offers, `target` may take it with E (TakeOffer). Public, like the hand item both avatars show.
## Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var giver: int
var target: int


func _init(by: int, to: int) -> void:
	giver = by
	target = to


func event_name() -> StringName:
	return &"OfferMade"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"giver": giver, "target": target}
