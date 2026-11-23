class_name AvatarClips
extends RefCounted
## The avatar's state to its clip (#522, ARCHITECTURE §4.7.53): a pure function, state in, the
## clip to play (or RAGDOLL: no clip, the physical bones) out. The state is what a client may draw:
## a remote avatar's from its interpolated poses (the drawn move between two drawn frames, the
## pose's yaw and `crouched` bit) and the public events it already received (its hand item), never
## a claimed or host velocity (invariant 7; a source test holds it); the own avatar's from its
## local movement. The clip names are the art MVP set's as Godot imports them (the import contract,
## tools/assets/asset_contract.json, lists each one this table can return).
##
## Checked in this order:
## knocked down or a dead body -> RAGDOLL; posed (#1296) -> SEATED (Crouch_Idle if crouched), still
## whatever the drawn move; slower than MIN_SPEED_MPS -> Crouch_Idle or Idle;
## crouched -> Crouch_Fwd, past halfway from the crouch's speed to the fast crouch's Crouch_Run
## where the character has it (#1334; whatever the heading); in Locomotion's back family (beyond
## about 100 degrees off the body's forward, with its dead zone, #1334) -> Jog_Bwd; more to a side
## than ahead -> Strafe_Left or Strafe_Right; ahead up to WALK_UP_TO_MPS -> Walk where the character
## has it; ahead at most halfway from the walk to the sprint speed -> Jog_Fwd, faster ->
## Sprint_Fwd. That clip is the plan's `base`, the nearest
## point of the art MVP set; the rig plays a family's move as a blend of its points at the plan's
## `blend` (the direction) and switches families by the plan's `slot`. A move clip
## plays at the drawn speed over its ground speed at rate 1 (the art's "play at speed /
## speed_m_s"), clamped to MIN_RATE..MAX_RATE. Holding a two-handed item adds the Carry_Upper layer
## over any of them (carry idle = Idle + Carry_Upper, carry walk = Jog_Fwd + Carry_Upper). Picking
## up and putting down are one-shots on the item events (one_shot()), not states.

enum Shot { PICKUP, PUTDOWN }

## Not a clip: the body is a ragdoll on the skeleton's physical bones (the knockdown ADR's KE7).
const RAGDOLL := &"@ragdoll"
const IDLE := &"Idle"
const JOG_FWD := &"Jog_Fwd"
const JOG_BWD := &"Jog_Bwd"
const STRAFE_LEFT := &"Strafe_Left"
const STRAFE_RIGHT := &"Strafe_Right"
const SPRINT_FWD := &"Sprint_Fwd"
const CROUCH_IDLE := &"Crouch_Idle"
const CROUCH_FWD := &"Crouch_Fwd"
## The optional move clips (#1334, the art's table): a slow forward move's and the fast crouch's;
## a character without them plays Jog_Fwd and Crouch_Fwd there (EXTRA_CLIPS).
const WALK := &"Walk"
const CROUCH_RUN := &"Crouch_Run"
const EXTRA_CLIPS: Array[StringName] = [WALK, CROUCH_RUN]
## The seated watcher's clip (#1296; GDD §12): Idle until the art set has a seated clip, which no
## character has yet (blocked on art). Not a decision.
const SEATED := IDLE
## The upper-body layer over the base clip while carrying (the rig filters it to Torso and below).
const CARRY_UPPER := &"Carry_Upper"
const PICKUP_ONE := &"Pickup_One"
const PUTDOWN_ONE := &"Putdown_One"
const PICKUP_PACKAGE := &"Pickup_Package"
const PUTDOWN_PACKAGE := &"Putdown_Package"

## Below this drawn speed the avatar stands: the footsteps' threshold, so a body that steps moves.
const MIN_SPEED_MPS := FootstepCadence.MIN_SPEED_MPS
## The move clips' ground speed at rate 1, in m/s (the art handoff's table, slice_m1/HANDOFF.md).
const JOG_MPS := 4.5
const SPRINT_MPS := 7.0
const CROUCH_MPS := 0.75
## Walk's and Crouch_Run's ground speeds at rate 1 (the table: Walk at rate 2.398 at 2.0 m/s,
## Crouch_Run at rate 1 at 2.8 m/s).
const WALK_MPS := 2.0 / 2.398
const CROUCH_RUN_MPS := 2.8
## A forward move plays Walk up to this drawn speed, then the front family (the table's "Walk up
## to about 2 m/s, then a blend into the jog", the engineer's list of 2026-10-26): the slots'
## cross-fade is the blend. Client feel, not a game number: the host checks no clip.
const WALK_UP_TO_MPS := 2.0
## The rate clamp: a placeholder, "not a decision" (wide enough for the fast crouch over 0.75 m/s).
const MIN_RATE := 0.25
const MAX_RATE := 4.0


## What the avatar does, as drawn.
class State:
	extends RefCounted
	## Knocked down (the snapshot's `downed` flag).
	var downed := false
	## A dead player's body (BodyViews).
	var dead_body := false
	## The drawn horizontal move, in m/s: the drawn position's change over the drawn frame.
	var drawn_move := Vector3.ZERO
	## The body's yaw (the pose's), radians; forward is -Z turned by it.
	var yaw := 0.0
	## The public seated pose (#1296).
	var posed := false
	## The public crouch bit (#790).
	var crouched := false
	## Holding a two-handed item (the package) in the hand.
	var carrying := false
	## Whether the last plan was in the back family (Plan.back): the family switch's dead zone.
	var was_back := false


## What to play.
class Plan:
	extends RefCounted
	## The base clip, or RAGDOLL.
	var base: StringName = IDLE
	## Its speed scale.
	var rate := 1.0
	## The Carry_Upper layer on.
	var carry := false
	## The rig's base input: the clip for Idle, Sprint_Fwd and the crouch's, else the move's family
	## (Locomotion.FRONT or BACK), blended at `blend`.
	var slot: StringName = IDLE
	## The move's direction in the body's frame (Locomotion.blend_position()); zero standing.
	var blend := Vector2.ZERO
	## Whether the move is in the back family (feeds the next State.was_back).
	var back := false


## The plan for `state`, with the mode's walk and sprint speeds and its crouch's and fast crouch's
## (the client's PlayerRules); `extras`: the EXTRA_CLIPS the drawn character has (CharacterSet's or
## CharacterRig's extra_clips()), none: Jog_Fwd and Crouch_Fwd stand in for them.
static func plan(
	state: State,
	walk_mps: float,
	sprint_mps: float,
	crouch_mps := 0.0,
	crouch_fast_mps := 0.0,
	extras: Array[StringName] = [],
) -> Plan:
	var out := Plan.new()
	if state.downed or state.dead_body:
		out.base = RAGDOLL
		return out
	out.carry = state.carrying
	out.back = state.was_back
	if state.posed:
		out.base = CROUCH_IDLE if state.crouched else SEATED
		out.slot = out.base
		return out
	var flat := Vector3(state.drawn_move.x, 0.0, state.drawn_move.z)
	var speed := flat.length()
	if not is_finite(speed) or not is_finite(state.yaw) or speed < MIN_SPEED_MPS:
		out.base = CROUCH_IDLE if state.crouched else IDLE
		out.slot = out.base
		return out
	if state.crouched:
		var run := extras.has(CROUCH_RUN) and crouch_fast_mps > crouch_mps
		if run and speed > (crouch_mps + crouch_fast_mps) * 0.5:
			out.base = CROUCH_RUN
			out.rate = _rate(speed, CROUCH_RUN_MPS)
		else:
			out.base = CROUCH_FWD
			out.rate = _rate(speed, CROUCH_MPS)
		out.slot = out.base
		return out
	var heading := Locomotion.heading_of(flat, state.yaw)
	out.blend = Locomotion.blend_position(heading)
	out.back = Locomotion.family_of(heading, state.was_back) == Locomotion.BACK
	out.slot = Locomotion.BACK if out.back else Locomotion.FRONT
	if out.back:
		out.base = JOG_BWD
		out.rate = _rate(speed, JOG_MPS)
	elif absf(out.blend.x) > out.blend.y:
		out.base = STRAFE_RIGHT if out.blend.x > 0.0 else STRAFE_LEFT
		out.rate = _rate(speed, JOG_MPS)
	elif speed > (walk_mps + sprint_mps) * 0.5:
		out.base = SPRINT_FWD
		out.slot = out.base
		out.rate = _rate(speed, SPRINT_MPS)
	elif speed <= WALK_UP_TO_MPS and extras.has(WALK):
		out.base = WALK
		out.slot = out.base
		out.rate = _rate(speed, WALK_MPS)
	else:
		out.base = JOG_FWD
		out.rate = _rate(speed, JOG_MPS)
	return out


## plan() with `rules`' speeds (none: zero, as without a mode) for a character with `extras`.
static func plan_by(state: State, rules: PlayerRules, extras: Array[StringName] = []) -> Plan:
	if rules == null:
		return plan(state, 0.0, 0.0, 0.0, 0.0, extras)
	return plan(
		state,
		rules.walk_speed_mps,
		rules.sprint_speed_mps,
		rules.crouch_speed_mps,
		rules.crouch_fast_speed_mps,
		extras
	)


## The ground speed at rate 1 the table's rates assume for the move clip `clip` (JOG_MPS,
## SPRINT_MPS, CROUCH_MPS, WALK_MPS, CROUCH_RUN_MPS); 0 for a clip that does not move. A character
## measured otherwise plays it faster or slower (CharacterRig.rate_factor, #1693).
static func assumed_mps(clip: StringName) -> float:
	match clip:
		JOG_FWD, JOG_BWD, STRAFE_LEFT, STRAFE_RIGHT:
			return JOG_MPS
		SPRINT_FWD:
			return SPRINT_MPS
		CROUCH_FWD:
			return CROUCH_MPS
		WALK:
			return WALK_MPS
		CROUCH_RUN:
			return CROUCH_RUN_MPS
	return 0.0


## The one-shot clip for picking up or putting down an item, two-handed (the package) or not.
static func one_shot(shot: Shot, two_handed: bool) -> StringName:
	if shot == Shot.PICKUP:
		return PICKUP_PACKAGE if two_handed else PICKUP_ONE
	return PUTDOWN_PACKAGE if two_handed else PUTDOWN_ONE


## The base clips the table can return (RAGDOLL aside): the art MVP set's, which every character
## must have (CharacterSet); Locomotion's optional points are never among them.
static func base_clips() -> Array[StringName]:
	return [IDLE, JOG_FWD, JOG_BWD, STRAFE_LEFT, STRAFE_RIGHT, SPRINT_FWD, CROUCH_IDLE, CROUCH_FWD]


## The one-shot clips one_shot() can return.
static func shot_clips() -> Array[StringName]:
	return [PICKUP_ONE, PUTDOWN_ONE, PICKUP_PACKAGE, PUTDOWN_PACKAGE]


## Every clip the avatar plays: the bases, the carry layer and the one-shots.
static func all_clips() -> Array[StringName]:
	var out := base_clips()
	out.append(CARRY_UPPER)
	out.append_array(shot_clips())
	return out


static func _rate(speed: float, natural: float) -> float:
	return clampf(speed / natural, MIN_RATE, MAX_RATE)
