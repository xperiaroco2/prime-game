class_name FootstepCadence
extends RefCounted
## When a walking player's next footstep falls (#525; ARCHITECTURE §4.7.38), pure: one per player
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

## Below this horizontal speed a player stands. A placeholder, "not a decision".
const MIN_SPEED_MPS := 0.5
## The time between two steps at the mode's walk and at its sprint speed. Placeholders, "not a
## decision" (the engineer's listening session tunes them).
const WALK_INTERVAL_S := 0.45
const SPRINT_INTERVAL_S := 0.32
## Where a cadence starts, and starts again: half a step, so the first step of a walk from rest
## falls half an interval after it starts.
const START := 0.5

## How far through the present step, 0 to 1.
var progress := START


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


## Whether a step falls in this frame, in which the feet moved `moved` in `delta` seconds; at most
## one per frame. A placement starts the cadence again and plays none.
func advance(moved: Vector3, delta: float, walk_mps: float, sprint_mps: float) -> bool:
	if delta <= 0.0:
		return false
	var horizontal := Vector2(moved.x, moved.z).length()
	if horizontal > SnapshotBuffer.SNAP_SPEED_MPS * delta:
		reset()
		return false
	var interval := interval_s(horizontal / delta, walk_mps, sprint_mps)
	if is_inf(interval):
		return false
	progress += delta / interval
	if progress < 1.0:
		return false
	progress = fmod(progress, 1.0)
	return true


## Starts the cadence again (a placement, a life change).
func reset() -> void:
	progress = START
