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
## knocked down or a dead body -> RAGDOLL; slower than MIN_SPEED_MPS -> Crouch_Idle or Idle;
## crouched -> Crouch_Fwd (the only crouched move clip, whatever the heading); within 45 degrees
## of the body's back -> Jog_Bwd; more to a side than ahead -> Strafe_Left or Strafe_Right; ahead
## at most halfway from the walk to the sprint speed -> Jog_Fwd, faster -> Sprint_Fwd. A move clip
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
## The rate clamp: a placeholder, "not a decision" (wide enough for the fast crouch over 0.75 m/s).
const MIN_RATE := 0.25
const MAX_RATE := 4.0
## Within this angle of the body's back the move is backward (else a side wins over ahead).
const BACK_RAD := PI * 0.25


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
	## The public crouch bit (#790).
	var crouched := false
	## Holding a two-handed item (the package) in the hand.
	var carrying := false


## What to play.
class Plan:
	extends RefCounted
	## The base clip, or RAGDOLL.
	var base: StringName = IDLE
	## Its speed scale.
	var rate := 1.0
	## The Carry_Upper layer on.
	var carry := false


## The plan for `state`, with the mode's walk and sprint speeds (the client's PlayerRules).
static func plan(state: State, walk_mps: float, sprint_mps: float) -> Plan:
	var out := Plan.new()
	if state.downed or state.dead_body:
		out.base = RAGDOLL
		return out
	out.carry = state.carrying
	var flat := Vector3(state.drawn_move.x, 0.0, state.drawn_move.z)
	var speed := flat.length()
	if not is_finite(speed) or not is_finite(state.yaw) or speed < MIN_SPEED_MPS:
		out.base = CROUCH_IDLE if state.crouched else IDLE
		return out
	if state.crouched:
		out.base = CROUCH_FWD
		out.rate = _rate(speed, CROUCH_MPS)
		return out
	# The move in the body's frame: -Z ahead, +X to its right.
	var local := Basis(Vector3.UP, state.yaw).inverse() * flat
	var ahead := -local.z
	if ahead < -speed * cos(BACK_RAD):
		out.base = JOG_BWD
		out.rate = _rate(speed, JOG_MPS)
	elif absf(local.x) > ahead:
		out.base = STRAFE_RIGHT if local.x > 0.0 else STRAFE_LEFT
		out.rate = _rate(speed, JOG_MPS)
	elif speed > (walk_mps + sprint_mps) * 0.5:
		out.base = SPRINT_FWD
		out.rate = _rate(speed, SPRINT_MPS)
	else:
		out.base = JOG_FWD
		out.rate = _rate(speed, JOG_MPS)
	return out


## The one-shot clip for picking up or putting down an item, two-handed (the package) or not.
static func one_shot(shot: Shot, two_handed: bool) -> StringName:
	if shot == Shot.PICKUP:
		return PICKUP_PACKAGE if two_handed else PICKUP_ONE
	return PUTDOWN_PACKAGE if two_handed else PUTDOWN_ONE


## The base clips the table can return (RAGDOLL aside).
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
