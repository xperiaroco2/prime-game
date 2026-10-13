class_name PhotoPrintedEvent
extends MatchEvent
## A photo was printed (ARCHITECTURE §4.2, §9.5; the photo ADR §2.6, PE8, #782) by an accepted
## Interact at the printer: the photo's item id, which the ItemSpawned right before announced on
## the printer's tray, and the shot it shows (ShotTaken's `shot`), so a client binds the photo to
## the picture it drew for that shot. One per shot of the film, in shot order; the film's
## ItemVanished follows the last. It names no player and never says whether a person is in the
## shot (PE5). Audience: everyone (every shot was public already).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The photo's item id.
var item: int
## The shot it shows.
var shot: int


func _init(item_id: int, shot_id: int) -> void:
	item = item_id
	shot = shot_id


func event_name() -> StringName:
	return &"PhotoPrinted"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"item": item, "shot": shot}
