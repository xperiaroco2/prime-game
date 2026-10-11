class_name SwitchChangedEvent
extends MatchEvent
## A switch of the Generator (ARCHITECTURE §4.2, §9.5; the Generator ADR's GE6, GE9, #797) was
## toggled by an accepted Interact: its station id (StationPlaced's) and whether it is on now. A
## placed switch starts off, so the deal sends none; a fixed switch is no station and never has
## one (GE14). It names no player: nobody is told who switched (§1.1 row 18), held apart from this
## declaration by generator_events_test.gd. Audience: everyone (GE6: a client shows it only where
## the eye or the ear reaches).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The switch's station id.
var station: int
var on: bool


func _init(station_id: int, is_on: bool) -> void:
	station = station_id
	on = is_on


func event_name() -> StringName:
	return &"SwitchChanged"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "on": on}
