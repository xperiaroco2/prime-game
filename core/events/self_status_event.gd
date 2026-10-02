class_name SelfStatusEvent
extends MatchEvent
## One player's own numbers (ARCHITECTURE §4.2, §5, §7.1): health and stamina in thousandths
## (§3.3), whether sprint is available now, and the client tick of the player's last claim the
## host settled (#155). Private numbers are never avatar fields, so they travel only here. Sent on
## change, at most once per tick (SelfStatusFeed). Audience: only that player.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY

var peer: int
var health: int
var stamina: int
## Whether holding sprint puts the player in the sprint state on its next tick (Q7).
var sprint_available: bool
## The client tick of the last MoveClaim the host accepted and settled for this player in its
## epoch (PlayerState.claim_tick), or -1 for none since its placement: the stamina is the number
## after that claim, and the player's client settles its later claims on top (PredictedStamina).
var claim_tick: int


func _init(
	to_peer: int, health_now: int, stamina_now: int, can_sprint: bool, settled_claim := -1
) -> void:
	peer = to_peer
	health = health_now
	stamina = stamina_now
	sprint_available = can_sprint
	claim_tick = settled_claim


func event_name() -> StringName:
	return &"SelfStatus"


func audience() -> Audience:
	return Audience.only(peer)


func to_dict() -> Dictionary:
	return {
		"health": health,
		"stamina": stamina,
		"sprint_available": sprint_available,
		"claim_tick": claim_tick,
	}
