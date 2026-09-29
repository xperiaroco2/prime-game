class_name SpikeMoveCheck
extends RefCounted
## Spike (#14): the host's crude check of client-side movement (ARCHITECTURE §7). Clients move
## themselves and report positions. Per peer the host keeps a distance budget that refills at
## max_speed x slack and holds burst_seconds of that, so bunched packets pass. What it stops:
## a sustained speed above max_speed x slack, any single step over teleport_distance, and
## positions outside the bounds box. What it lets through, on purpose for a crude check: up to
## slack (25 %) over max_speed for ever; a blink of up to teleport_distance after standing
## still; walking through walls (only the outer box is checked); any height inside the box
## (vertical movement is not checked). Only horizontal distance spends budget.
## Pure logic: the caller passes the time, so tests need no scene.

enum Verdict { ACCEPTED, STALE, TELEPORT, SPEED, BOUNDS }

const VERDICT_NAMES: PackedStringArray = ["accepted", "stale", "teleport", "speed", "bounds"]

## Horizontal speed the host allows, m/s; walk_spike.gd sets its walking speed here.
var max_speed := 6.0
## Budget refill factor over max_speed, for jitter between the client's and the host's clocks.
var slack := 1.25
## Seconds of movement the budget can hold.
var burst_seconds := 0.5
## Any single step longer than this is a teleport, whatever the budget, in metres.
var teleport_distance := 2.0
## The box a position must stay in.
var bounds := AABB(Vector3(-10.0, -1.0, -6.0), Vector3(20.0, 4.0, 12.0))

# peer id -> {pos: Vector3, epoch: int, budget: float}
var _peers: Dictionary[int, Dictionary] = {}


## Puts a peer at pos in a new epoch: its spawn, or a correction. Moves from older epochs are
## stale from now on. Returns the new epoch, to send to the client with the position.
func place(peer: int, pos: Vector3) -> int:
	var epoch: int = (_peers[peer]["epoch"] as int) + 1 if _peers.has(peer) else 1
	_peers[peer] = {"pos": pos, "epoch": epoch, "budget": 0.0}
	return epoch


func forget(peer: int) -> void:
	_peers.erase(peer)


func has_peer(peer: int) -> bool:
	return _peers.has(peer)


func position_of(peer: int) -> Vector3:
	return _peers[peer]["pos"]


func epoch_of(peer: int) -> int:
	return _peers[peer]["epoch"]


## Refills every peer's budget; call once per host frame, before reading that frame's packets.
## One long frame (a host hitch) may refill past the cap: the moves queued during it arrive
## together right after it.
func advance(delta: float) -> void:
	var gain := max_speed * slack * delta
	var cap := maxf(max_speed * slack * burst_seconds, gain)
	for peer: int in _peers:
		var state: Dictionary = _peers[peer]
		state["budget"] = minf((state["budget"] as float) + gain, cap)


## Checks a reported move. Accepted moves become the peer's position and spend budget; anything
## else leaves the peer where it was. The caller corrects the client on TELEPORT, SPEED and BOUNDS.
func check(peer: int, epoch: int, pos: Vector3) -> Verdict:
	var state: Dictionary = _peers[peer]
	if epoch != state["epoch"]:
		return Verdict.STALE
	if not bounds.has_point(pos):
		return Verdict.BOUNDS
	var from: Vector3 = state["pos"]
	var step := Vector2(pos.x - from.x, pos.z - from.z).length()
	if step > teleport_distance:
		return Verdict.TELEPORT
	if step > (state["budget"] as float):
		return Verdict.SPEED
	state["budget"] = (state["budget"] as float) - step
	state["pos"] = pos
	return Verdict.ACCEPTED
