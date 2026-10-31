class_name GillFlippedEvent
extends MatchEvent
## The ship's engine's overheat (ARCHITECTURE §4.2, §9.5.27; GDD §8, the throat's gill sets): a
## press of the gill set's button `station` flipped the slit under the white bar, `slit` (0, the
## mouth side, to 4), now `open` (cyan) or shut again (red). It names no player: the gills are seen
## by whoever stands in the throat. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The gill set's button station.
var station: int
## The slit flipped, 0 (the mouth side) to 4.
var slit: int
## Whether it is open now.
var open: bool


func _init(station_id: int, slit_index: int, is_open: bool) -> void:
	station = station_id
	slit = slit_index
	open = is_open


func event_name() -> StringName:
	return &"GillFlipped"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "slit": slit, "open": open}
