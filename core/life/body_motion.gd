class_name BodyMotion
extends RefCounted
## The motion of a knocked-down body (the knockdown rework's KE3, §4): PlayerState.motion while the
## host's physics moves the body, null at rest. core/ holds no physics: the point is
## PlayerState.position and the velocity PlayerState.velocity, which server/'s reports set
## (BodyMoved, KE14; LifeRules.body_moved).

## The epoch of the knockdown that started it (its Correction's and its LaunchBody's): a report
## naming another is dropped.
var epoch := 0
## Where the body rests when its capsule finds no floor (§4, step 6): the floor below the last
## accepted position at the knockdown (step 2), asked once then.
var fallback := Vector3.ZERO
## The reports slower than the rest speed since the last faster one, or since the knockdown (KE15):
## counted only in ticks that brought this body's report, so a freeze's catch-up ticks never fill
## the rest time.
var slow_reports := 0
## The ticks since the knockdown, counted by LifeTicks in every tick, reports or not: the longest
## motion.
var ticks := 0


func _init(knockdown_epoch: int, rests_at: Vector3) -> void:
	epoch = knockdown_epoch
	fallback = rests_at
