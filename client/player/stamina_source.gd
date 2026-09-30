@abstract class_name StaminaSource
extends RefCounted
## What the controller asks about stamina, and how it reports what it spent (ARCHITECTURE §7.1).
## The controller holds no stamina rule of its own: it asks before a sprint or a jump and reports
## each physics step. `LocalStamina` is this issue's stand-in; `core/`'s stamina replaces it
## (stage 2d in #30), and the client then predicts from the same rules and follows `SelfStatus`.
## `ghost` is the player's life state: stamina never limits a ghost (the engineer's correction of
## 2026-09-30), so a source never refuses a ghost and records nothing for it.

## Whether the player may be in the sprint state this step, given whether it was last step.
@abstract func can_sprint(was_sprinting: bool, ghost: bool) -> bool

## Whether a jump may start now.
@abstract func can_jump(ghost: bool) -> bool

## Reports one physics step of `delta` seconds: whether the player was in the sprint state and
## moved horizontally, and whether it jumped.
@abstract func report(delta: float, sprinted_moving: bool, jumped: bool, ghost: bool) -> void

## The current stamina, for the HUD (4c) and tests.
@abstract func get_stamina() -> float
