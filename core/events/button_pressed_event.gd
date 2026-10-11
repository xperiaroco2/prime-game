class_name ButtonPressedEvent
extends MatchEvent
## The Generator's button was pressed by an accepted Interact (ARCHITECTURE §4.2, §9.5; the
## Generator ADR's GE6, GE9, #797), whether or not the press started or stopped the charge (the
## charge's own progress event says that): the generator's station id (StationPlaced's). It names
## no player: nobody is told who pressed (§1.1 row 18), held apart from this declaration by
## generator_events_test.gd. Audience: everyone (GE6: a client shows it only where the eye or the
## ear reaches).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The generator's station id.
var station: int


func _init(station_id: int) -> void:
	station = station_id


func event_name() -> StringName:
	return &"ButtonPressed"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station}
