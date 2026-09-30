class_name LocalStamina
extends StaminaSource
## STAND-IN until the client follows `core/`'s `SelfStatus` (M3); keep no other copy of these
## rules. It predicts with the rule of `core/`'s `StaminaLedger` (stage 2d, #60), ARCHITECTURE
## §7.1 and Q7 of the MVP rules ADR:
## - Walking always works.
## - The sprint state starts when sprint is held and stamina is at least
##   `sprint_start_stamina`, and lasts while it is held and stamina is above 0.
## - A step in the sprint state in which the player gave movement input and moved horizontally
##   costs `sprint_cost_per_second` per second; every other step regenerates `regen_per_second`. A
##   pushed player pays nothing for the push, even while it holds sprint (the engineer's decision
##   of 2026-09-30); the controller reports only its own movement.
## - A jump needs at least `jump_cost` and spends it at once.
## - A ghost's stamina never limits it (the engineer's correction of 2026-09-30): a ghost may
##   always sprint and jump, and its steps change nothing.

var stamina: float

var _tuning: PlayerTuning


func _init(tuning: PlayerTuning) -> void:
	_tuning = tuning
	stamina = tuning.max_stamina


func can_sprint(was_sprinting: bool, ghost: bool) -> bool:
	if ghost:
		return true
	if was_sprinting:
		return stamina > 0.0
	return stamina >= _tuning.sprint_start_stamina


func can_jump(ghost: bool) -> bool:
	return ghost or stamina >= _tuning.jump_cost


func report(delta: float, sprinted_moving: bool, jumped: bool, ghost: bool) -> void:
	if ghost:
		return
	if jumped:
		stamina -= _tuning.jump_cost
	if sprinted_moving:
		stamina -= _tuning.sprint_cost_per_second * delta
	else:
		stamina += _tuning.regen_per_second * delta
	stamina = clampf(stamina, 0.0, _tuning.max_stamina)


func get_stamina() -> float:
	return stamina
