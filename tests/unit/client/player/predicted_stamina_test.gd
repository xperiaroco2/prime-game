extends GdUnitTestSuite
## PredictedStamina (ARCHITECTURE §4.7 and §7.1, the M4 ADR's E24) against `core/`'s StaminaLedger
## with the same PlayerRules: three 60 Hz steps make a 20 Hz tick, and after every tick the
## prediction holds exactly the ledger's thousandths, sprinting until empty, regenerating, holding
## sprint without moving and jumping. It follows each SelfStatus, gates sprint and jump by its own
## number (Q7), and the downed (the ghost flag until M4-9) are never limited.

const STEP := 1.0 / 60.0

var _rules := FixtureModes.player_rules()


func test_starts_full() -> void:
	var stamina := PredictedStamina.new(_rules)
	assert_float(stamina.get_stamina()).is_equal(float(_rules.stamina))
	assert_int(stamina.stamina).is_equal(Ticks.thousandths(_rules.stamina))


func test_a_sprint_until_empty_and_on_matches_the_ledger_every_tick() -> void:
	_assert_matches_the_ledger(200, true, true)


func test_regeneration_from_empty_matches_the_ledger_every_tick() -> void:
	_assert_matches_the_ledger(60, false, true, 0)


func test_sprint_held_without_moving_matches_the_ledger_every_tick() -> void:
	_assert_matches_the_ledger(60, true, false, 40000)


func test_a_jump_costs_what_the_ledger_spends() -> void:
	var stamina := PredictedStamina.new(_rules)
	stamina.set_status(50000)
	var player := _ledger_player(50000)
	stamina.report(0.0, false, true, false)
	StaminaLedger.spend(player, Ticks.thousandths(_rules.jump_cost))
	assert_int(stamina.stamina).is_equal(player.stamina)


func test_sprint_needs_the_start_threshold_and_lasts_until_zero() -> void:
	var stamina := PredictedStamina.new(_rules)
	var start := Ticks.thousandths(_rules.sprint_start)
	stamina.set_status(start)
	assert_bool(stamina.can_sprint(false, false)).is_true()
	stamina.set_status(start - 1)
	assert_bool(stamina.can_sprint(false, false)).is_false()
	stamina.set_status(1)
	assert_bool(stamina.can_sprint(true, false)).is_true()
	stamina.set_status(0)
	assert_bool(stamina.can_sprint(true, false)).is_false()


func test_a_jump_needs_its_full_cost() -> void:
	var stamina := PredictedStamina.new(_rules)
	var cost := Ticks.thousandths(_rules.jump_cost)
	stamina.set_status(cost)
	assert_bool(stamina.can_jump(false)).is_true()
	stamina.set_status(cost - 1)
	assert_bool(stamina.can_jump(false)).is_false()


func test_each_self_status_resets_the_prediction_within_bounds() -> void:
	var stamina := PredictedStamina.new(_rules)
	stamina.set_status(12345)
	assert_int(stamina.stamina).is_equal(12345)
	stamina.set_status(-5)
	assert_int(stamina.stamina).is_equal(0)
	stamina.set_status(Ticks.thousandths(_rules.stamina) + 1)
	assert_int(stamina.stamina).is_equal(Ticks.thousandths(_rules.stamina))


func test_the_downed_may_always_sprint_and_jump_and_record_nothing() -> void:
	var stamina := PredictedStamina.new(_rules)
	stamina.set_status(0)
	assert_bool(stamina.can_sprint(false, true)).is_true()
	assert_bool(stamina.can_jump(true)).is_true()
	stamina.report(1.0, true, true, true)
	assert_int(stamina.stamina).is_equal(0)


## Runs `ticks` ticks of 60 Hz steps holding sprint (`held`) and moving (`moving`), from `from`
## thousandths (full when -1), and compares with the ledger after every tick.
func _assert_matches_the_ledger(ticks: int, held: bool, moving: bool, from := -1) -> void:
	var start := Ticks.thousandths(_rules.stamina) if from < 0 else from
	var stamina := PredictedStamina.new(_rules)
	stamina.set_status(start)
	var player := _ledger_player(start)
	var sprinting := false
	var went_empty := false
	for tick: int in range(1, ticks + 1):
		for step: int in 3:
			sprinting = held and stamina.can_sprint(sprinting, false)
			stamina.report(STEP, sprinting and moving, false, false)
		StaminaLedger.settle(player, _rules, tick, held, moving)
		(
			assert_int(stamina.stamina)
			. override_failure_message(
				"tick %d: %d, the ledger %d" % [tick, stamina.stamina, player.stamina]
			)
			. is_equal(player.stamina)
		)
		assert_bool(sprinting).is_equal(player.sprinting)
		went_empty = went_empty or player.stamina == 0
	if held and moving and from < 0:
		assert_bool(went_empty).is_true()


func _ledger_player(thousandths: int) -> PlayerState:
	var player := PlayerState.new(1, "P1")
	player.stamina = thousandths
	player.stamina_settled_tick = 0
	return player
