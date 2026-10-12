class_name FilmLoadedEvent
extends MatchEvent
## A film was loaded into the photo camera (ARCHITECTURE §4.2, §9.5; the photo ADR §2.2, #781) by
## an accepted Interact: the camera's station id (StationPlaced's) and the film's item id, which
## now lies at the camera (Items.lay_on_station: no ItemPlaced). It names no player: who stood at
## the camera is what the snapshots show (PD13). Audience: everyone (a client shows the film in
## the camera and, from then on, the viewfinder instead of the load).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The camera's station id.
var station: int
## The film's item id.
var item: int


func _init(station_id: int, item_id: int) -> void:
	station = station_id
	item = item_id


func event_name() -> StringName:
	return &"FilmLoaded"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "item": item}
