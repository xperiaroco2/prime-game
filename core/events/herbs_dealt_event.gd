class_name HerbsDealtEvent
extends MatchEvent
## Cooking's herbs of the round (ARCHITECTURE §4.2, §9.5; the cooking ADR's CE8, CE9, CD13 (b),
## #772), sent once by the deal after the orders: `code`, the herb's item kind id per icon (icon i
## means code[i], what the herb board shows), and `beds`, the herb's item kind id per herb bed in
## station order (which herb grows on which bed this round). Both lists are as long as the task's
## herbs. An honest client draws the code only on the herb board and each bed's herb only on that
## bed (§3 of the ADR). It names no player, held apart from this declaration by a unit test.
## Audience: everyone (as the Generator's GE6 (a)).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The herb's item kind id per icon index.
var code: PackedStringArray
## The herb's item kind id per bed, in station order.
var beds: PackedStringArray


func _init(code_ids: PackedStringArray, bed_ids: PackedStringArray) -> void:
	code = code_ids
	beds = bed_ids


func event_name() -> StringName:
	return &"HerbsDealt"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"code": code, "beds": beds}
