class_name PlayerState
extends RefCounted
## One player of the roster in MatchState (ARCHITECTURE §3.1): a peer whose Hello was accepted.
## Health and stamina are thousandths (§3.3). The movement rule (2d) keeps the last accepted
## MoveClaim here, and every range rule reads it (§7.1).

## The life states of vision revision 1 (§3.1): alive, downed, dead, or left. 0 health knocks a
## living player down for the knockdown time, then it dies (LifeRules, LifeTicks); a player who
## leaves mid-round is left. DOWNED took the ghosts' value, and that value is never reused for DEAD.
enum Life { ALIVE, DOWNED, DEAD, LEFT }

var peer: int
var name: String
## The body colour, an index into PlayerColours (#551): public, kept for the session (ResetMatch
## leaves it), set at the join and by SetProfile in the lobby.
var colour := 0
var ready := false
## A GameRole id, or empty before the deal.
var role: StringName
var life := Life.ALIVE
## The host tick at which the current life state runs out, or -1: while downed, the knockdown's end,
## when LifeTicks lets the player die (§3.4); while dead, the respawn's (M4-3). -1 while a raise
## pauses the knockdown (M4-4): knockdown_left holds what is left of it then.
var life_deadline := -1
## While a raise pauses a downed player's knockdown (RaiseDowned, M4-4), the host ticks it had
## left; the knockdown runs on from there when the raise stops. -1 otherwise.
var knockdown_left := -1
## The first host tick at which strikes hit the player again, or -1 (LifeRules.make_invulnerable,
## after a respawn or a revive): it is invulnerable at every tick before it (is_invulnerable).
var invulnerable_until := -1
## The last accepted claim (§7.1).
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var facing := Vector3.FORWARD
var on_floor := true
## The client tick of the last accepted claim, or -1.
var claim_tick := -1
## Raised by every placement; a claim of another epoch is dropped as stale (§7).
var epoch := 0
## The hand item's id, or -1: the hand slot (vision revision 1, Two hands).
var held_item := -1
## The belt item's id, or -1: the belt slot, which holds at most one one-handed item and is
## visible to everyone, as the hand item is.
var belt_item := -1
var health := 0
var stamina := 0
## The host tick up to which stamina is settled (§7.1), or -1.
var stamina_settled_tick := -1
var sprinting := false
## The last accepted claim's sprint flag, and whether it gave movement input and moved
## horizontally: settle_ahead() settles the ticks no claim covers yet with them (§7.1).
var sprint_held := false
var moving := false


func _init(peer_id: int, player_name: String) -> void:
	peer = peer_id
	name = player_name


## Whether the player is living: ALIVE only, never downed or dead.
func is_alive() -> bool:
	return life == Life.ALIVE


## Whether strikes skip the player at host tick `tick` (vision revision 1, V8): nothing ends it
## before invulnerable_until, not even the player's own attack (the engineer's answer 3, PR #133).
func is_invulnerable(tick: int) -> bool:
	return tick < invulnerable_until


func is_present() -> bool:
	return life != Life.LEFT
