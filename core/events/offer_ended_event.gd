class_name OfferEndedEvent
extends MatchEvent
## `giver`'s offer to `target` ended (ARCHITECTURE §4.2, §7.1; #1434): taken, cancelled, or ended
## by OfferTicks or EndOffers. Public, as OfferMade. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var giver: int
var target: int


func _init(by: int, to: int) -> void:
	giver = by
	target = to


func event_name() -> StringName:
	return &"OfferEnded"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"giver": giver, "target": target}
