@abstract class_name StaminaSource
extends RefCounted
## What the controller asks about stamina, and how it reports what it spent (ARCHITECTURE §7.1).
## The controller holds no stamina rule of its own: it asks before a sprint or a jump and reports
## each physics step. `PredictedStamina` predicts with `core/`'s rule (`StaminaLedger`, 2d) and
## follows `SelfStatus` (M4-7, E24).
## `downed` is the player's life state (the controller's life): only the living sprint and
## jump, so a source refuses both to the downed, and their stamina regenerates as usual (M4-2's
## crawl check, StaminaLedger).

## Whether the player may be in the sprint state this step, given whether it was last step.
@abstract func can_sprint(was_sprinting: bool, downed: bool) -> bool

## Whether a jump may start now.
@abstract func can_jump(downed: bool) -> bool

## Reports one physics step of `delta` seconds: whether the player was in the sprint state, gave
## movement input and moved horizontally (a push alone does not count), and whether it jumped.
@abstract func report(delta: float, sprinted_moving: bool, jumped: bool, downed: bool) -> void

## The current stamina, for the HUD (4c) and tests.
@abstract func get_stamina() -> float
