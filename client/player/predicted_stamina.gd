class_name PredictedStamina
extends StaminaSource
## The local player's stamina (ARCHITECTURE §4.7 and §7.1, the M4 ADR's E24): predicted between
## SelfStatus updates with the rule of `core/`'s StaminaLedger, of which this is the client's only
## copy, and set to each SelfStatus as it arrives. Sprint and jump are gated by the prediction, so a
## player whose stamina ran out stops sprinting at once rather than a round trip later. The numbers
## are the client's own copy of the mode's PlayerRules (the content hash makes them the host's).
##
## The rule, in thousandths per 20 Hz tick like the ledger's, so both count the same:
## - The physics steps' time is cut into ticks (Ticks.RATE); each tick costs the sprint cost per
##   tick when its last step was in the sprint state with the player's own movement, and
##   regenerates the regeneration per tick otherwise, up to the maximum (a push is free, the
##   engineer's decision of 2026-09-30).
## - The sprint state starts at `sprint_start` and lasts while sprint is held and stamina is
##   above 0; a jump needs its full cost and spends it at once (Q7).
## - Only the living sprint and jump: the downed (the controller's ghost flag) crawl, are never in
##   the sprint state and regenerate as usual, since they spend none (M4-2's crawl check).

const TICK_SECONDS := 1.0 / Ticks.RATE
## Float rounding of 1/60 s steps must not lose a tick.
const _CARRY_SLACK := 1e-6

## Thousandths of a point (§3.3), like SelfStatus.
var stamina := 0

var _most := 0
var _sprint_start := 0
var _jump_cost := 0
var _cost := 0
var _regen := 0
## Seconds of steps not yet settled as a tick.
var _carry := 0.0


func _init(rules: PlayerRules) -> void:
	_most = Ticks.thousandths(rules.stamina)
	_sprint_start = Ticks.thousandths(rules.sprint_start)
	_jump_cost = Ticks.thousandths(rules.jump_cost)
	_cost = Ticks.per_tick(rules.sprint_cost_per_s)
	_regen = Ticks.per_tick(rules.stamina_regen_per_s)
	stamina = _most


## The host's number from a SelfStatus (thousandths): the prediction goes on from there.
func set_status(thousandths: int) -> void:
	stamina = clampi(thousandths, 0, _most)


func can_sprint(was_sprinting: bool, downed: bool) -> bool:
	if downed:
		return false
	if was_sprinting:
		return stamina > 0
	return stamina >= _sprint_start


func can_jump(downed: bool) -> bool:
	return not downed and stamina >= _jump_cost


func report(delta: float, sprinted_moving: bool, jumped: bool, downed: bool) -> void:
	# The downed spend nothing (StaminaLedger): their steps only regenerate.
	sprinted_moving = sprinted_moving and not downed
	if jumped and not downed:
		stamina = maxi(0, stamina - _jump_cost)
	_carry += delta
	while _carry >= TICK_SECONDS - _CARRY_SLACK:
		_carry -= TICK_SECONDS
		if sprinted_moving:
			stamina = maxi(0, stamina - _cost)
		else:
			stamina = mini(_most, stamina + _regen)


## In points, for the HUD and tests.
func get_stamina() -> float:
	return stamina / float(Ticks.THOUSANDTHS)
