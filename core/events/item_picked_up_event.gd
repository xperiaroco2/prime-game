class_name ItemPickedUpEvent
extends MatchEvent
## A player took an item (ARCHITECTURE §4.2, §7.1): a `PickUp` from the floor, or a take that
## gives one (Items.give: a box's, a bed's, the grill's; the cooking ADR, §2). `belted` names the
## item this take put on the belt, or -1:
## - the hand item, one-handed, stayed in its place, now on the belt, and `item` went into a free
##   place, now in the hand (E29);
## - `item` itself, which went straight onto the belt while a two-handed item stays in the hand
##   (the cooking ADR, CD3 (b), CE20, CE21): a fold must not put `item` in the hand then.
## A hand item that did not fit the belt rests where the picked item lay (a pickup's swap,
## ItemPlaced `swap` after this event) or at the taker's feet (a give, ItemPlaced `put_down` before
## it); a full belt's item a take beside a two-handed item displaces goes to the feet the same way,
## before this event. `place` is the place (0..2, GDD §6) `item` went into: the selected one when
## `item` went into the hand (a take into a free place selects it), a belt place when `belted` is
## `item`. Who carries what is public. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
var item: int
var belted: int
var place: int


func _init(by_peer: int, item_id: int, belted_id: int = -1, place_id: int = 0) -> void:
	peer = by_peer
	item = item_id
	belted = belted_id
	place = place_id


func event_name() -> StringName:
	return &"ItemPickedUp"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "item": item, "belted": belted, "place": place}
