class_name BurgerServedEvent
extends MatchEvent
## A burger was served at Cooking's order board (ARCHITECTURE §4.2, §9.5; the cooking ADR's
## amendment of 2026-10-15, #1101): `station` the station id of the place it was plated on (its
## order's), `right` whether it was the order's burger. Only "right" or "wrong": never which part
## was wrong (the cook works that out from the burger and the order). Right: the order is done
## (TaskState and TaskProgress follow); wrong: the burger is thrown away. Its burger's ItemVanished
## follows. It names no player (the ADR's §3, "Who did it"). Audience: everyone, as every cooking
## event (the ADR's §3; the task's success or error at the board is heard by anyone near).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The place's station id.
var station: int
## Whether the burger was the order's.
var right: bool


func _init(station_id: int, is_right: bool) -> void:
	station = station_id
	right = is_right


func event_name() -> StringName:
	return &"BurgerServed"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "right": right}
