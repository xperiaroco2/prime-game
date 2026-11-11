class_name MirrorPlacesEvent
extends MatchEvent
## The lobby mirror's places in use, the whole list (ARCHITECTURE §4.2, §7.1.23; #1394): each
## held place's station and the peer holding it, in station order (empty: every place free). Sent on
## every change (Mirror.announce), and again to everyone when a player joins (MirrorTicks). Public:
## who stands at the mirror is seen by all, and the holder's client opens its menu from it.
## Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The held places' stations, in station order.
var stations: PackedInt32Array
## The peer holding each, in the same order.
var peers: PackedInt32Array


func _init(place_stations := PackedInt32Array(), holders := PackedInt32Array()) -> void:
	stations = place_stations
	peers = holders


func event_name() -> StringName:
	return &"MirrorPlaces"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"stations": stations, "peers": peers}
