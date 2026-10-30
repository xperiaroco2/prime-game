class_name DrunkFeel
extends RefCounted
## The own drunk player's feel (#1391; GDD §3 Base mode, "The bar"; ARCHITECTURE §4.7.6 "Drunk"):
## pure maths of a strength 0..1, an own clock in seconds and a seed (the own peer id, a phase per
## player), with the numbers of PlayerTuning's Drunk group. The sway rolls and pitches the own
## camera, never its yaw; the drift turns the walk's direction about UP and keeps its length, so a
## drifting walk is never faster than the keys' (the host's MovementRule allows it as it is, with no
## allowance). No randomness and no Node: the same strength, clock and seed give the same answer.

## The second wave of a sway or a drift starts this many turns later than the first, so the two do
## not peak together at clock 0.
const SECOND_PHASE := 0.37
## Spreads the seeds' phases over the turn (the golden ratio's fraction).
const SEED_SPREAD := 0.618034


## How strong the effect is for the drunk value `drunk`: 0 sober, 1 at `full_at` (the mode's
## PlayerRules.drunk_too_much_at) and above, `curve` the exponent between (1 linear; 0 or less
## also linear). 0 when `full_at` is 0 or less: a mode with no bar.
static func strength(drunk: int, full_at: int, curve: float) -> float:
	if drunk <= 0 or full_at <= 0:
		return 0.0
	var ratio := clampf(float(drunk) / float(full_at), 0.0, 1.0)
	return pow(ratio, curve) if curve > 0.0 else ratio


## `current` moved toward `target` by one step of `delta` seconds, at a rate that crosses the whole
## 0..1 range in `ease_seconds` (0 or less: at once). Never past `target`.
static func eased(current: float, target: float, delta: float, ease_seconds: float) -> float:
	if ease_seconds <= 0.0:
		return target
	return move_toward(current, target, delta / ease_seconds)


## The camera's sway at `clock`: x the roll, y the pitch, in radians, each within the tuning's
## sway_roll_max_deg / sway_pitch_max_deg times `strength`.
static func sway(
	strength_now: float, clock: float, phase_seed: int, tuning: PlayerTuning
) -> Vector2:
	if strength_now <= 0.0:
		return Vector2.ZERO
	var phase := _phase_of(phase_seed)
	var roll := _wave(clock, tuning.sway_period_s, tuning.sway_second_period_s, phase)
	# The pitch runs a quarter turn behind the roll: the view circles instead of nodding.
	var pitch := _wave(clock, tuning.sway_period_s, tuning.sway_second_period_s, phase + 0.25)
	return (
		Vector2(
			deg_to_rad(tuning.sway_roll_max_deg) * roll,
			deg_to_rad(tuning.sway_pitch_max_deg) * pitch
		)
		* strength_now
	)


## The walk's drift at `clock`, in radians about UP: a wander of up to drift_wander_deg plus a
## steady lean of drift_lean_deg to one side (the seed's), both times `strength`; at most
## (drift_wander_deg + drift_lean_deg) times `strength` either way.
static func drift_angle(
	strength_now: float, clock: float, phase_seed: int, tuning: PlayerTuning
) -> float:
	if strength_now <= 0.0:
		return 0.0
	var wander := _wave(
		clock, tuning.drift_period_s, tuning.drift_second_period_s, _phase_of(phase_seed)
	)
	var side := 1.0 if phase_seed % 2 == 0 else -1.0
	return (
		deg_to_rad(tuning.drift_wander_deg * wander + tuning.drift_lean_deg * side) * strength_now
	)


## The most drift_angle() turns the walk at full strength, in radians.
static func max_drift_angle(tuning: PlayerTuning) -> float:
	return deg_to_rad(absf(tuning.drift_wander_deg) + absf(tuning.drift_lean_deg))


## `direction` turned by `angle` radians about UP: the same length.
static func drifted(direction: Vector3, angle: float) -> Vector3:
	if is_zero_approx(angle):
		return direction
	return direction.rotated(Vector3.UP, angle)


## Two sines of the periods `period_s` and `second_s` (0 or less: that sine is off), averaged so
## the sum stays within -1..1; `phase` in turns.
static func _wave(clock: float, period_s: float, second_s: float, phase: float) -> float:
	var sum := 0.0
	if period_s > 0.0:
		sum += sin(TAU * (clock / period_s + phase))
	if second_s > 0.0:
		sum += sin(TAU * (clock / second_s + phase + SECOND_PHASE))
	return sum * 0.5


static func _phase_of(phase_seed: int) -> float:
	return fposmod(float(phase_seed) * SEED_SPREAD, 1.0)
