class_name CrystalChangedEvent
extends MatchEvent
## The ship's engine's burnt crystal (ARCHITECTURE §4.2, §9.5.27; GDD §8 "A spent cartridge"): the
## crystal of the socket `station` after each change. `item` is the crystal out of its socket as an
## item, or -1 while the socket holds it (fitted, or returned by a blast: the item vanished).
## `charger` is the charger station holding it (the item locked in its slot, no other event moves
## it), or -1; `phase` that charger's phase (CrystalProblem's EMPTY, LOADED, CHARGING or WAITING;
## EMPTY without a charger); while CHARGING `tick` is the host tick the charge ends on (the back
## panel's fill), else -1. Sent at the pull (ItemSpawned before it, ItemPickedUp after), the load,
## the press, the charge's end, the take, the fit and the blast. It names no player. Audience:
## everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The socket station.
var station: int
## The charger holding the crystal, or -1.
var charger: int
## CrystalProblem's charger phase.
var phase: int
## The crystal out of its socket, or -1.
var item: int
## The host tick the charge ends on while charging, else -1.
var tick: int


func _init(
	socket_id: int, charger_id: int, charger_phase: int, item_id: int, end_tick: int
) -> void:
	station = socket_id
	charger = charger_id
	phase = charger_phase
	item = item_id
	tick = end_tick


func event_name() -> StringName:
	return &"CrystalChanged"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "charger": charger, "phase": phase, "item": item, "tick": tick}
