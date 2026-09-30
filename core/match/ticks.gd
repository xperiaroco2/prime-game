class_name Ticks
extends RefCounted
## Time in core/ is host ticks (ARCHITECTURE §3.3). Data holds seconds and whole points per
## second; Match converts them once, with one rounding rule: toward zero.

## The core tick rate, in ticks per second (a placeholder, MVP rules).
const RATE := 20
## Health and stamina are integers in thousandths of a point (§3.3).
const THOUSANDTHS := 1000
## Absorbs the float error of a product such as 0.35 * 20 = 7.000000000000001 or 6.999999999.
const _EPSILON := 1e-9


## Seconds to whole ticks, rounded toward zero: 5 s is 100 ticks, 0.5 s is 10.
static func from_seconds(seconds: float) -> int:
	return _toward_zero(seconds * RATE)


## Minutes to whole ticks, rounded toward zero: 10 min is 12000 ticks.
static func from_minutes(minutes: float) -> int:
	return _toward_zero(minutes * 60.0 * RATE)


## An amount per second, in whole points, to thousandths per tick, rounded toward zero:
## 15 points per second is 750 thousandths per tick.
static func per_tick(points_per_second: float) -> int:
	return _toward_zero(points_per_second * THOUSANDTHS / RATE)


## Whole points to thousandths: 100 health is 100000.
static func thousandths(points: float) -> int:
	return _toward_zero(points * THOUSANDTHS)


static func _toward_zero(value: float) -> int:
	if value >= 0.0:
		return int(floorf(value + _EPSILON))
	return -int(floorf(-value + _EPSILON))
