class_name DamagedEvent
extends MatchEvent
## A player took damage (ARCHITECTURE §4.2, §5): the amount and the health left, in thousandths
## (§3.3). Only the victim learns it: another player's health and damage never leave the host, and
## the attacker gets no confirmation of a hit. No field names the attacker. Audience: only the
## victim.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY

var peer: int
## The damage taken, in thousandths.
var amount: int
## The victim's health after it, in thousandths.
var health: int


func _init(victim: int, taken: int, health_left: int) -> void:
	peer = victim
	amount = taken
	health = health_left


func event_name() -> StringName:
	return &"Damaged"


func audience() -> Audience:
	return Audience.only(peer)


func to_dict() -> Dictionary:
	return {"amount": amount, "health": health}
