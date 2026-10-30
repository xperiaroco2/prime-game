class_name PlayerState
extends RefCounted
## One player of the roster in MatchState (ARCHITECTURE §3.1): a peer whose Hello was accepted.
## Health and stamina are thousandths (§3.3). The movement rule (2d) keeps the last accepted
## MoveClaim here, and every range rule reads it (§7.1).

## The life states of vision revision 1 (§3.1): alive, downed, dead, or left. 0 health knocks a
## living player down for the knockdown time, then it dies (LifeRules, LifeTicks); a player who
## leaves mid-round is left. DOWNED took the ghosts' value, and that value is never reused for DEAD.
enum Life { ALIVE, DOWNED, DEAD, LEFT }

## The number of item places: the hand and the two belt slots (GDD §6).
const PLACES := 3
## last_place at the start and after clear_places(): the first belt place, so the first X (Swap)
## of a fresh player hangs its hand item on the belt, as the swap of one belt slot did.
const FIRST_LAST_PLACE := 1

var peer: int
var name: String
## The player's number in the host session (§3.5, the returning-players ADR, Decision 2): the
## digits of its fallback name Player<number>, never sent on its own. Set at the join
## (MatchState.give_number); a player who leaves and joins again where joins are allowed gets it
## back by its return key, which only MatchState.numbers holds: no PlayerState holds a key, so no
## event built from a player's fields can carry one. 0 for a player added without a join (tests).
var number := 0
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
## The last accepted claim's crouch (the crouch ADR, KE2): false at every placement and knockdown,
## never taken from a downed claim; kept in every phase, the crouch plays everywhere (#991). The eye
## and the capsule read it (PlayerRules.height_of, eye_height_of), and the snapshot relays it.
var crouched := false
## The last accepted claim's sneak (#990): a standing pose, never with `crouched` (the crouch wins);
## false at every placement, knockdown, raise and respawn, never taken from a downed claim, kept in
## every phase like the crouch. The snapshot relays it; each listener's client silences the steps
## of a sneaking body only at the crouch walk's speed (FootstepCadence.silent_of).
var sneaking := false
## The seated pose (#1296; GDD §12 "The camera wall"): set by TakePose (the Pose intent, where the
## mode's rule allows it); ended by any own move, that is a claim with moving input, a moved tick
## it covers or a new jump, even one the host refuses, or an accepted claim's travel with no one
## near to push it (MovementRule), and at every placement, knockdown, respawn and reset.
## Public body state: the snapshot relays it to every peer. The host keeps the standing capsule
## and eye for it (only `crouched` lowers them).
var posed := false
## How drunk the player is (#1390; GDD §3 Base mode, "The bar"): 0 is sober, up to the mode's
## PlayerRules.drunk_max. Raised by Drink (a mug's Use), lowered one point per
## PlayerRules.drunk_point_s by DrunkTicks, and back to 0 (sober()) at every placement, knockdown,
## respawn and reset, so nobody is drunk in a round. Public body state: the snapshot relays it on
## the avatar to every other peer, and the player's own SelfStatus carries it to its own client
## (the sway and the drift, #1391, read it; the fact `drunk_too_much` marks Drink's upward
## crossing of PlayerRules.drunk_too_much_at, #1393).
var drunk := 0
## The host tick at which the next drunk point falls (DrunkTicks), or -1 while sober. Host only,
## never sent.
var drunk_stamp := -1
## The client tick of the last accepted claim, or -1.
var claim_tick := -1
## Raised by every placement; a claim of another epoch is dropped as stale (§7).
var epoch := 0
## The three item places, the hand and the two belt slots (GDD §6 "Drawing from the belt", #1040
## c6320249563): each an item id or -1. An item keeps its place; `selected_place` is in the hand,
## the other two hang on the belt. Index 0..2 here and on the wire; the HUD and the keys say 1..3.
## Only Items moves items between them (a two-handed item is only ever in the selected place);
## clear_places() resets them. All of it is public, as the avatar's hand and belt are.
var places := PackedInt32Array([-1, -1, -1])
## The place in the hand, 0..2. Items.select is its one writer (a Draw, X, a take into a free
## place).
var selected_place := 0
## The place held before the selected one, 0..2, never equal to it: X (Swap) goes back to it.
var last_place := FIRST_LAST_PLACE
## The hand item's id, or -1: the selected place's item (vision revision 1, Two hands). Writing
## it writes the selected place.
var held_item: int:
	get:
		return places[selected_place]
	set(value):
		places[selected_place] = value
## The belt items' ids, or -1: the item of the lower- and of the higher-numbered place not
## selected, each visible to everyone, as the hand item is. Not compacted: an empty lower place
## leaves `belt_item` -1 beside a `belt_item2`. Read-only: Items writes `places`.
var belt_item: int:
	get:
		return places[belt_places()[0]]
var belt_item2: int:
	get:
		return places[belt_places()[1]]
var health := 0
var stamina := 0
## The host tick up to which stamina is settled (§7.1), or -1.
var stamina_settled_tick := -1
var sprinting := false
## The last accepted claim's sprint flag, and whether it gave movement input and moved
## horizontally: settle_ahead() settles the ticks no claim covers yet with them (§7.1).
var sprint_held := false
var moving := false
## The knocked-down body's motion while the host's physics moves it (the knockdown rework's KE3),
## or null: at rest, and for every player not knocked down on a map PlayerRules.motion_maps lists.
var motion: BodyMotion = null
## The limp (#1393; GDD §3 Base mode, "The bar"; ARCHITECTURE §7.1.21), or null: a drinker past
## too much lies as a rag-doll while its life stays ALIVE (not downed). LifeRules.go_limp starts it
## (GoLimp, a reaction on the fact drunk_too_much), LimpTicks pushes it and gets the player up
## (LifeRules.get_up), and every placement, reset, knockdown, death and leave ends it
## (LifeRules.clear_limp). Public body state: the snapshot relays it to every peer, the player's
## own client included (its own avatar).
var limp: LimpState = null


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


## Whether the player lies limp (#1393): living, its body moved by the host, not by its claims.
func is_limp() -> bool:
	return limp != null


## Whether the host holds the player's body still against its claims: downed or limp. Its claims
## give only a facing (MovementRule), and the host's physics moves its body.
func holds_still() -> bool:
	return life == Life.DOWNED or limp != null


## The two places not selected, the lower first: the belt.
func belt_places() -> PackedInt32Array:
	var belt := PackedInt32Array()
	for place in PLACES:
		if place != selected_place:
			belt.append(place)
	return belt


## The place that holds `item_id`, or -1.
func place_of(item_id: int) -> int:
	if item_id < 0:
		return -1
	return places.find(item_id)


## The ids the player carries, the hand's first, then the belt's in place order: the order a
## death or a leave drops them in.
func carried_items() -> PackedInt32Array:
	var carried := PackedInt32Array()
	if held_item >= 0:
		carried.append(held_item)
	for place in belt_places():
		if places[place] >= 0:
			carried.append(places[place])
	return carried


## Sobers the player up: drunk 0, no stamp. True when it was drunk, so a caller with a context
## touches its SelfStatus (SelfStatusFeed).
func sober() -> bool:
	var was := drunk > 0
	drunk = 0
	drunk_stamp = -1
	return was


## Empties every place; place 0 is in the hand again (MatchState.reset_player).
func clear_places() -> void:
	places = PackedInt32Array([-1, -1, -1])
	selected_place = 0
	last_place = FIRST_LAST_PLACE
