class_name SelfStatusEvent
extends MatchEvent
## One player's own numbers (ARCHITECTURE §4.2, §5, §7.1): health and stamina in thousandths
## (§3.3), whether sprint is available now, and the client tick of the player's last claim the
## host settled (#155), whether the player is posed (#1383) and its wheel pose (#1485). Private
## numbers are never avatar fields, so they travel only here; `posed` and `wheel_pose` are avatar
## fields every other peer sees, but a client gets no avatar of its own (Snapshots), so its own
## poses come here too. Sent on change, at most once per tick (SelfStatusFeed). Audience: only that
## player.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY

var peer: int
var health: int
var stamina: int
## Whether holding sprint puts the player in the sprint state on its next tick (Q7).
var sprint_available: bool
## The client tick of the last MoveClaim the host accepted and settled for this player in its
## epoch, or -1 for none since its placement (MovementRule.settled_claim_tick): the stamina is the
## number after that claim, and the player's client settles its later claims on top
## (PredictedStamina). After a jump or a StaminaCost, the number also holds the ticks the host
## settled ahead of the claims (StaminaLedger.settle_ahead, up to the ledger's lag), which the
## client settles again until a later status (ARCHITECTURE §7.1, "Accepted").
var claim_tick: int
## How drunk the player is (PlayerState.drunk, #1390): the same number every other peer sees on its
## avatar, here for the own client, which gets no own avatar (the sway, #1391).
var drunk: int
## Whether the player sits in the seated pose (PlayerState.posed, TakePose): its own client gets no
## avatar of itself, so it learns it sits only here (#1383).
var posed: bool
## The player's wheel pose as its byte (PlayerState.wheel_pose_code, WheelPoseCode; 0 for none): its
## own client learns its own pose only here (#1485).
var wheel_pose: int


func _init(
	to_peer: int,
	health_now: int,
	stamina_now: int,
	can_sprint: bool,
	settled_claim := -1,
	drunk_now := 0,
	is_posed := false,
	wheel_pose_code := 0
) -> void:
	peer = to_peer
	health = health_now
	stamina = stamina_now
	sprint_available = can_sprint
	claim_tick = settled_claim
	drunk = drunk_now
	posed = is_posed
	wheel_pose = wheel_pose_code


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
		"drunk": drunk,
		"posed": posed,
		"wheel_pose": wheel_pose,
	}
