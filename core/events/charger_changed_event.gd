class_name ChargerChangedEvent
extends MatchEvent
## The ship's engine's burnt crystal (ARCHITECTURE §4.2, §9.5.27; GDD §8, the charger): the charger
## `station` is now in `phase` (CrystalProblem's EMPTY, LOADED, CHARGING or WAITING) with the
## crystal `item` in its slot (-1 when empty; the item is locked there, no other event moves it),
## and while CHARGING `tick` is the host tick the charge ends on (the back panel's fill), else 0.
## It names no player. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The charger station.
var station: int
## CrystalProblem's charger phase.
var phase: int
## The crystal in its slot, or -1.
var item: int
## The host tick the charge ends on while charging, else 0.
var tick: int


func _init(station_id: int, charger_phase: int, item_id: int, end_tick: int) -> void:
	station = station_id
	phase = charger_phase
	item = item_id
	tick = end_tick


func event_name() -> StringName:
	return &"ChargerChanged"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "phase": phase, "item": item, "tick": tick}
