class_name FootstepCadence
extends RefCounted
## When a walking player's next footstep falls (#525; ARCHITECTURE §4.7.43), pure: one per player
## WorldSounds hears. It is fed how far the player's drawn feet moved in one physics frame: the
## local player's own movement, or a remote player's interpolated pose (SnapshotBuffer), never a
## claimed velocity (client/CLAUDE.md), so a peer that claims to stand while it runs still steps,
## and one that claims to run while it stands is silent.
##
## The step interval follows the horizontal speed: interval_s() keeps WALK_INTERVAL_S at the
## mode's walk speed and SPRINT_INTERVAL_S at its sprint speed, and the stride (the distance per
## step) between them is interpolated, and held below walk and above sprint speed. Below
## MIN_SPEED_MPS a player stands: no step, and the cadence keeps its place, so a frame of no
## movement between two snapshots never adds a step. A move farther than
## SnapshotBuffer.SNAP_SPEED_MPS could carry anyone in the frame is a placement (a respawn, a round
## start, the host's correction, a snapped pose): no step, and the cadence starts again.
##
## A step at the crouch walk's speed is quiet, anywhere (#792, #991, the crouch ADR's KD1 (b)):
## quiet_of() of the step's own speed (step_speed_mps), never the crouch flag. A sneaking player's
## step is silent (#989, #990): silent_of() reads the sneak flag the pose carries AND the step's own
## speed, so a peer that claims the sneak while it walks faster is heard as quiet_of() says.
##
## The clip mode (#1334, art #196): given the drawn body's AvatarClips plan and its clip's cycle,
## a step falls when the clip's phase crosses one of its foot contacts (Locomotion.contacts, the
## issue's table as fractions of the cycle): the phase runs at the plan's rate over the cycle, and
## starts at 0 when the plan's slot changes (the rig's Transition starts the new input) and on a
## placement. A plan whose clip has no contacts, or no cycle, falls back to the speed's interval.
## Both modes keep step_speed_mps, quiet_of() and silent_of() on the measured speed.

## Below this horizontal speed a player stands. A placeholder, "not a decision".
const MIN_SPEED_MPS := 0.5
## The time between two steps at the mode's walk and at its sprint speed. Placeholders, "not a
## decision" (the engineer's listening session tunes them).
const WALK_INTERVAL_S := 0.45
const SPRINT_INTERVAL_S := 0.32
## Where a cadence starts, and starts again: half a step, so the first step of a walk from rest
## falls half an interval after it starts.
const START := 0.5
## The quiet step (the crouch ADR's KD1 (b) as #991 changed it, #792): a step at or below the
## mode's crouch_speed_mps plays this much quieter (added to the muffle's volume_db) and is heard
## only within QUIET_STEP_RANGE_M (SoundChooser.step's cut and the player's max_distance; a walk's
## step: SoundChooser.HEARING_RANGE_M); both ease to a walk's at the fast crouch's
## crouch_fast_speed_mps (quiet_of(); the ease is a placeholder). Client feel, no game rule the
## host reads. Placeholders, "not a decision" (the engineer's listening session tunes them).
const QUIET_STEP_DB := -6.0
const QUIET_STEP_RANGE_M := 6.0
## The sneak's silent step (#990): how far above the crouch walk's speed a sneaking step's measured
## speed may be and still be silent, so an interpolated pose's jitter never lets an honest sneak at
## crouch_speed_mps be heard. An engine tolerance, kept as built: the engineer's answer 1a on
## PR #1007 (comment 6166558510).
const SNEAK_SPEED_MARGIN_MPS := 0.2

## How far through the present step, 0 to 1.
var progress := START
## The horizontal speed of the step that fell last: the distance walked since the step before it
## (or since the cadence started) over the time spent moving, so one jittery frame of an
## interpolated pose never sets it (quiet_of() reads it).
var step_speed_mps := 0.0

var _walked_m := 0.0
var _walked_s := 0.0
## The clip mode's phase through the clip's cycle, 0 to 1, and the slot it runs in.
var _phase := 0.0
var _slot := &""


## The time between two steps at `speed_mps` for a mode that walks at `walk_mps` and sprints at
## `sprint_mps`; INF while standing (below MIN_SPEED_MPS) or for a mode with no speed.
static func interval_s(speed_mps: float, walk_mps: float, sprint_mps: float) -> float:
	if speed_mps < MIN_SPEED_MPS:
		return INF
	var t := 0.0
	if sprint_mps > walk_mps:
		t = clampf((speed_mps - walk_mps) / (sprint_mps - walk_mps), 0.0, 1.0)
	var stride := lerpf(walk_mps * WALK_INTERVAL_S, sprint_mps * SPRINT_INTERVAL_S, t)
	if stride <= 0.0:
		return INF
	return stride / speed_mps


## How quiet a step at `speed_mps` is, 0 (a walk's step) to 1 (QUIET_STEP_DB, QUIET_STEP_RANGE_M):
## 1 at or below `quiet_mps` (the mode's crouch_speed_mps), 0 at or above `loud_mps` (its
## crouch_fast_speed_mps, #991), linear between (a placeholder ease). Read from the speed, never the
## crouch flag (KD1 (b)), so a fast crouched peer is a walker's loudness and a slow walker is quiet.
## 0 for a mode with no crouch speed; a hard edge at `quiet_mps` where `loud_mps` is not above it
## (PlayerRules.check lets the two speeds be equal).
static func quiet_of(speed_mps: float, quiet_mps: float, loud_mps: float) -> float:
	if quiet_mps <= 0.0:
		return 0.0
	if loud_mps <= quiet_mps:
		return 1.0 if speed_mps <= quiet_mps else 0.0
	return clampf((loud_mps - speed_mps) / (loud_mps - quiet_mps), 0.0, 1.0)


## Whether a step at `speed_mps` is silent (#990): only while `sneaking` (the drawn pose's
## flag) and at or below the mode's `crouch_speed_mps` (the sneak's speed, #989) plus
## SNEAK_SPEED_MARGIN_MPS; never in a mode with no crouch speed.
static func silent_of(sneaking: bool, speed_mps: float, crouch_speed_mps: float) -> bool:
	if not sneaking or crouch_speed_mps <= 0.0:
		return false
	return speed_mps <= crouch_speed_mps + SNEAK_SPEED_MARGIN_MPS


## Whether a step falls in this frame, in which the feet moved `moved` in `delta` seconds; at most
## one per frame. A placement starts the cadence again and plays none. A step that falls sets
## step_speed_mps. With `plan` (the drawn body's AvatarClips plan) and `clip_cycle_s` (its base
## clip's length at rate 1), the step falls on the clip's contacts (the clip mode).
func advance(
	moved: Vector3,
	delta: float,
	walk_mps: float,
	sprint_mps: float,
	plan: AvatarClips.Plan = null,
	clip_cycle_s := 0.0
) -> bool:
	if delta <= 0.0:
		return false
	var horizontal := Vector2(moved.x, moved.z).length()
	if horizontal > SnapshotBuffer.SNAP_SPEED_MPS * delta:
		reset()
		return false
	if plan != null and plan.slot != _slot:
		_slot = plan.slot
		_phase = 0.0
	var contacts := Locomotion.contacts(plan.base) if plan != null else PackedFloat32Array()
	if not contacts.is_empty() and clip_cycle_s > 0.0 and plan.rate > 0.0:
		return _advance_clip(horizontal, delta, contacts, plan.rate / clip_cycle_s)
	var interval := interval_s(horizontal / delta, walk_mps, sprint_mps)
	if is_inf(interval):
		return false
	_walked_m += horizontal
	_walked_s += delta
	progress += delta / interval
	if progress < 1.0:
		return false
	progress = fmod(progress, 1.0)
	return _step()


## Starts the cadence again (a placement, a life change).
func reset() -> void:
	progress = START
	_walked_m = 0.0
	_walked_s = 0.0
	_phase = 0.0
	_slot = &""


## The clip mode: the phase runs `cycles_per_s`; a step when it crosses a contact (a fraction of
## the cycle), at most one a frame. Standing (below MIN_SPEED_MPS) holds the phase.
func _advance_clip(
	horizontal: float, delta: float, contacts: PackedFloat32Array, cycles_per_s: float
) -> bool:
	if horizontal / delta < MIN_SPEED_MPS:
		return false
	_walked_m += horizontal
	_walked_s += delta
	var from := _phase
	var to := from + delta * cycles_per_s
	_phase = fmod(to, 1.0)
	for contact: float in contacts:
		if (from < contact and contact <= to) or (from < contact + 1.0 and contact + 1.0 <= to):
			return _step()
	return false


## A step fell: its speed is the distance walked since the last over the time spent moving.
func _step() -> bool:
	step_speed_mps = _walked_m / _walked_s
	_walked_m = 0.0
	_walked_s = 0.0
	return true
