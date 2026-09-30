class_name SelfStatusEvent
extends MatchEvent
## One player's own numbers (ARCHITECTURE §4.2, §5, §7.1): health and stamina in thousandths
## (§3.3), and whether sprint is available now. Private numbers are never avatar fields, so they
## travel only here. Sent on change, at most once per tick (SelfStatusFeed). Audience: only that
## player.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY

var peer: int
var health: int
var stamina: int
## Whether holding sprint puts the player in the sprint state on its next tick (Q7).
var sprint_available: bool


func _init(to_peer: int, health_now: int, stamina_now: int, can_sprint: bool) -> void:
	peer = to_peer
	health = health_now
	stamina = stamina_now
	sprint_available = can_sprint


func event_name() -> StringName:
	return &"SelfStatus"


func audience() -> Audience:
	return Audience.only(peer)


func to_dict() -> Dictionary:
	return {"health": health, "stamina": stamina, "sprint_available": sprint_available}
