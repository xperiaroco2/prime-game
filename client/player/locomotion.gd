class_name Locomotion
extends RefCounted
## The aliens' eight-direction locomotion as data and pure maths (#1334, ARCHITECTURE §4.7.53),
## from the art track's per-clip table (prime-game-art#196, PRs #326 and #328, copied into issue
## #1334): no Nodes, so every number is testable.
##
## A move's heading is its angle off the body's forward, in radians, positive to the body's left
## (heading_of()). Its blend position is the unit direction (x: the body's right, y: ahead), never
## scaled by the speed. The eight points fall into two families that are never blended into each
## other: front (Jog_Fwd, its two diagonals, the two strafes) and back (Jog_Bwd and its two
## diagonals). A move switches to the back family beyond SWITCH_DEG + SWITCH_DEAD_DEG off forward
## and back to the front below SWITCH_DEG - SWITCH_DEAD_DEG, so a heading near the switch never
## flickers (family_of()). The rig adds a point only when the character has its clip (POINTS lists
## the art's eight; slice_m1 has four, so the diagonals arrive by data with the alien GLBs).

## The families.
const FRONT := &"Front"
const BACK := &"Back"
## The switch between the families, degrees off forward, and its dead zone either way (the art's
## "around 100 degrees", "about +-10 degrees").
const SWITCH_DEG := 100.0
const SWITCH_DEAD_DEG := 10.0

## The eight points: clip, heading in degrees (positive: to the left), family, and whether the art
## MVP set (slice_m1, the import contract) has the clip. The names are the art table's.
const POINTS: Array[Dictionary] = [
	{"clip": &"Jog_Fwd", "heading_deg": 0.0, "family": FRONT, "required": true},
	{"clip": &"Jog_Fwd_Left", "heading_deg": 45.0, "family": FRONT, "required": false},
	{"clip": &"Strafe_Left", "heading_deg": 90.0, "family": FRONT, "required": true},
	{"clip": &"Jog_Fwd_Right", "heading_deg": -45.0, "family": FRONT, "required": false},
	{"clip": &"Strafe_Right", "heading_deg": -90.0, "family": FRONT, "required": true},
	{"clip": &"Jog_Bwd", "heading_deg": 180.0, "family": BACK, "required": true},
	{"clip": &"Jog_Bwd_Left", "heading_deg": 135.0, "family": BACK, "required": false},
	{"clip": &"Jog_Bwd_Right", "heading_deg": -135.0, "family": BACK, "required": false},
]

## The table's cycle and its left and right foot contacts, seconds at rate 1 (issue #1334's
## table). A footstep falls at a contact's phase (contact / cycle) of the playing clip, whatever
## its real length: at rate r the steps fall the contacts' times / r apart.
const CONTACTS: Dictionary[StringName, Array] = {
	&"Walk": [1.333, 0.0, 0.667],
	&"Jog_Fwd": [0.917, 0.0, 0.458],
	&"Sprint_Fwd": [0.667, 0.0, 0.375],
	&"Crouch_Fwd": [0.875, 0.0, 0.417],
	&"Crouch_Run": [0.667, 0.0, 0.333],
	&"Strafe_Left": [0.917, 0.0, 0.458],
	&"Strafe_Right": [0.917, 0.0, 0.458],
	&"Jog_Fwd_Left": [0.917, 0.0, 0.458],
	&"Jog_Fwd_Right": [0.917, 0.0, 0.458],
	&"Jog_Bwd": [0.583, 0.0, 0.292],
	&"Jog_Bwd_Left": [0.583, 0.0, 0.292],
	&"Jog_Bwd_Right": [0.583, 0.0, 0.292],
}


## The heading of the horizontal move `flat` against a body turned by `yaw` (forward is -Z turned
## by it): radians, positive to the left, -PI..PI.
static func heading_of(flat: Vector3, yaw: float) -> float:
	var local := Basis(Vector3.UP, yaw).inverse() * Vector3(flat.x, 0.0, flat.z)
	return atan2(-local.x, -local.z)


## The blend position of `heading`: the unit direction, x to the body's right, y ahead.
static func blend_position(heading: float) -> Vector2:
	return Vector2(-sin(heading), cos(heading))


## Whether a move at `heading` plays the back family, given whether the last one did.
static func family_of(heading: float, was_back: bool) -> StringName:
	var off := rad_to_deg(absf(wrapf(heading, -PI, PI)))
	var edge := SWITCH_DEG - SWITCH_DEAD_DEG if was_back else SWITCH_DEG + SWITCH_DEAD_DEG
	return BACK if off > edge else FRONT


## The fastest a move at `heading` in `family` may go, m/s: the back family at most `back_mps`
## (its diagonals too), any move's sideways part at most `side_mps`; INF without a cap. A cap of 0
## is none.
static func speed_cap(
	heading: float, family: StringName, side_mps: float, back_mps: float
) -> float:
	var cap := INF
	if family == BACK and back_mps > 0.0:
		cap = back_mps
	var side := absf(sin(heading))
	if side_mps > 0.0 and side > 0.0:
		cap = minf(cap, side_mps / side)
	return cap


## The points of `family`, in POINTS' order.
static func points_of(family: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for point: Dictionary in POINTS:
		if point["family"] == family:
			out.append(point)
	return out


## The clips POINTS names that the art MVP set lacks (the rig plays them only when present).
static func optional_clips() -> Array[StringName]:
	var out: Array[StringName] = []
	for point: Dictionary in POINTS:
		if not point["required"]:
			out.append(point["clip"] as StringName)
	return out


## The contact phases (0..1) of `clip`'s footsteps; empty for a clip with none (an idle).
static func contacts(clip: StringName) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var row: Array = CONTACTS.get(clip, [])
	for i: int in range(1, row.size()):
		out.append((row[i] as float) / (row[0] as float))
	return out


## The table's cycle of `clip` in seconds at rate 1; 0 for a clip it lacks.
static func cycle_s(clip: StringName) -> float:
	var row: Array = CONTACTS.get(clip, [])
	return row[0] as float if not row.is_empty() else 0.0
