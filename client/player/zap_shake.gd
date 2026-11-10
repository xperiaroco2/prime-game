class_name ZapShake
extends RefCounted
## The own camera's shake at the ship's zap (#1585; GDD §8 "The ship is in an emergency mode"): pure
## maths of the seconds left of a shake `seconds` long, with PlayerTuning's Zap numbers. It rolls
## and pitches the own camera, never its yaw, fading to nothing at its end; the head, whose look is
## the claim's facing, never shakes. No randomness: the same inputs give the same answer.


## The camera's shake with `left` of its `seconds` to go: x the roll, y the pitch, in radians; zero
## before its start and after its end.
static func angles(left: float, seconds: float, tuning: PlayerTuning) -> Vector2:
	if left <= 0.0 or seconds <= 0.0:
		return Vector2.ZERO
	var fade := clampf(left / seconds, 0.0, 1.0)
	var phase := TAU * tuning.zap_shake_hz * (seconds - left)
	# The pitch beats at another rate than the roll: the view jolts instead of circling.
	return (
		Vector2(
			deg_to_rad(tuning.zap_shake_roll_deg) * sin(phase),
			deg_to_rad(tuning.zap_shake_pitch_deg) * sin(phase * 1.3)
		)
		* fade
	)
