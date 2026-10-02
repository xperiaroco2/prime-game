extends GdUnitTestSuite
## PredictedStamina (ARCHITECTURE §4.7 and §7.1, the M4 ADR's E24) against `core/`'s StaminaLedger
## with the same PlayerRules: three 60 Hz steps make a 20 Hz tick, and after every tick the
## prediction holds exactly the ledger's thousandths, sprinting until empty, regenerating, holding
## sprint without moving and jumping. It follows each SelfStatus, gates sprint and jump by its own
## number (Q7), and the downed are never limited. Settled by the claims (#155), it holds the
## ledger's number after every claim, pays a claim's jumps after its ticks, keeps its prediction
## when a SelfStatus answers an older claim, and settles the claims in flight again on top of a
## number it did not predict.

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


func test_the_downed_never_sprint_or_jump_whatever_their_stamina() -> void:
	# M4-2's crawl check: only the living sprint, and a downed player's new jump is corrected.
	var stamina := PredictedStamina.new(_rules)
	assert_bool(stamina.can_sprint(false, true)).is_false()
	assert_bool(stamina.can_sprint(true, true)).is_false()
	assert_bool(stamina.can_jump(true)).is_false()
	stamina.set_status(0)
	assert_bool(stamina.can_sprint(false, true)).is_false()
	assert_bool(stamina.can_jump(true)).is_false()


func test_the_downed_regenerate_as_the_ledger_and_spend_nothing() -> void:
	# From empty, reported as sprinting, moving and jumping: StaminaLedger's downed player pays
	# nothing and regenerates, and the prediction matches it after every tick.
	var stamina := PredictedStamina.new(_rules)
	stamina.set_status(0)
	var player := _ledger_player(0)
	player.life = PlayerState.Life.DOWNED
	for tick: int in range(1, 41):
		for step: int in 3:
			stamina.report(STEP, true, step == 0, true)
		StaminaLedger.settle(player, _rules, tick, true, true)
		assert_int(stamina.stamina).is_equal(player.stamina)
	assert_int(stamina.stamina).is_greater(0)


func test_by_claims_it_holds_the_ledgers_number_and_state_after_every_claim() -> void:
	var stamina := PredictedStamina.new(_rules)
	stamina.follow_claims()
	var player := _ledger_player(Ticks.thousandths(_rules.stamina))
	# [covered, sprint, moved itself, downed]: a sprint until empty and on, a walk holding sprint
	# below the start threshold, standing holding sprint, a claim covering a freeze, the crawl.
	var claims: Array[Array] = []
	for i: int in 120:
		claims.append([1, true, true, false])
	for i: int in 30:
		claims.append([1, true, true, false] if i % 3 == 0 else [1, false, true, false])
	claims.append_array([[1, true, false, false], [5, true, true, false], [2, false, false, false]])
	claims.append_array([[3, true, true, true], [1, true, true, false]])
	var tick := 0
	var went_empty := false
	for claim: Array in claims:
		var covered: int = claim[0]
		tick += covered
		player.life = PlayerState.Life.DOWNED if claim[3] else PlayerState.Life.ALIVE
		stamina.settle_claim(covered, claim[1] as bool, claim[2] as bool, claim[3] as bool)
		StaminaLedger.settle(player, _rules, tick, claim[1] as bool, claim[2] as bool)
		(
			assert_int(stamina.stamina)
			. override_failure_message(
				"tick %d: %d, the ledger %d" % [tick, stamina.stamina, player.stamina]
			)
			. is_equal(player.stamina)
		)
		assert_bool(stamina.is_sprinting()).is_equal(player.sprinting)
		went_empty = went_empty or player.stamina == 0
	assert_bool(went_empty).is_true()


func test_by_claims_steps_spend_nothing_and_a_jump_is_paid_after_the_claims_ticks() -> void:
	var stamina := PredictedStamina.new(_rules)
	stamina.follow_claims()
	var full := Ticks.thousandths(_rules.stamina)
	var cost := Ticks.thousandths(_rules.jump_cost)
	stamina.report(STEP, true, true, false)
	stamina.report(STEP, true, false, false)
	stamina.report(STEP, true, false, false)
	# The jump shows at once and gates the next one, but the sprint state of the claim's ticks
	# reads the number before it, as the host's ledger does.
	assert_int(stamina.stamina).is_equal(full)
	assert_float(stamina.get_stamina()).is_equal((full - cost) / float(Ticks.THOUSANDTHS))
	stamina.set_status(cost + cost - 1)
	assert_bool(stamina.can_jump(false)).is_false()
	stamina.set_status(full)
	# A standing tick regenerates up to the maximum first, then the jump is paid: full less its cost.
	var player := _ledger_player(full)
	stamina.settle_claim(1, false, false, false)
	StaminaLedger.settle(player, _rules, 1, false, false)
	StaminaLedger.spend(player, cost)
	assert_int(stamina.stamina).is_equal(player.stamina)
	assert_float(stamina.get_stamina()).is_equal(player.stamina / float(Ticks.THOUSANDTHS))


func test_by_claims_a_self_status_of_an_older_claim_keeps_the_prediction() -> void:
	var stamina := PredictedStamina.new(_rules)
	stamina.follow_claims()
	# The first SelfStatus, before any claim, is taken as it is.
	stamina.follow_status(60000)
	var after: Array[int] = []
	for i: int in 5:
		stamina.settle_claim(1, true, true, false)
		after.append(stamina.stamina)
	# The host answered the third claim; the fourth and fifth are in flight.
	stamina.follow_status(after[2])
	assert_int(stamina.stamina).is_equal(after[4])
	stamina.follow_status(after[4])
	assert_int(stamina.stamina).is_equal(after[4])


func test_by_claims_a_number_it_did_not_predict_is_taken_with_the_claims_in_flight() -> void:
	var stamina := PredictedStamina.new(_rules)
	stamina.follow_claims()
	stamina.follow_status(60000)
	var player := _ledger_player(60000)
	var tick := 0
	var after: Array[int] = []
	for i: int in 5:
		stamina.settle_claim(1, true, true, false)
		after.append(stamina.stamina)
	# Two claims in flight when the third's answer came; then a sixth claim.
	stamina.follow_status(after[2])
	stamina.settle_claim(1, true, true, false)
	# The host's answer to the fourth claim carries a cost the client did not predict (a swing):
	# the fifth and the sixth are still in flight, and are settled again on top of it.
	for i: int in 4:
		tick += 1
		StaminaLedger.settle(player, _rules, tick, true, true)
	StaminaLedger.spend(player, 10000)
	stamina.follow_status(player.stamina)
	for i: int in 2:
		tick += 1
		StaminaLedger.settle(player, _rules, tick, true, true)
	assert_int(stamina.stamina).is_equal(player.stamina)
	assert_bool(stamina.is_sprinting()).is_equal(player.sprinting)
	# The next answer, to the fifth claim, is one it predicted again.
	var settled := stamina.stamina
	stamina.settle_claim(1, true, true, false)
	tick += 1
	StaminaLedger.settle(player, _rules, tick, true, true)
	assert_int(stamina.stamina).is_equal(player.stamina)
	stamina.follow_status(settled - Ticks.per_tick(_rules.sprint_cost_per_s))
	assert_int(stamina.stamina).is_equal(player.stamina)


## Reviewers of #155: a status that reached full stamina matched the newest claim and set the
## round trip to 0, so an unpredicted cost early in the next sprint gave back its claims in flight.
func test_by_claims_a_number_many_claims_left_keeps_the_round_trip_it_learnt() -> void:
	var stamina := PredictedStamina.new(_rules)
	stamina.follow_claims()
	var after: Array[int] = []
	for i: int in 2:
		stamina.settle_claim(1, false, false, false)
	for i: int in 5:
		stamina.settle_claim(1, true, true, false)
		after.append(stamina.stamina)
	# Two claims in flight: learnt from a number only one claim left.
	stamina.follow_status(after[2])
	# Back to full, which many claims leave: the host's answer tells no round trip.
	for i: int in 12:
		stamina.settle_claim(1, false, false, false)
	assert_int(stamina.stamina).is_equal(Ticks.thousandths(_rules.stamina))
	stamina.follow_status(stamina.stamina)
	# A sprint from full; the answer to its first claim carries a cost the client did not
	# predict, with two claims in flight.
	for i: int in 3:
		stamina.settle_claim(1, true, true, false)
	var player := _ledger_player(Ticks.thousandths(_rules.stamina))
	StaminaLedger.settle(player, _rules, 1, true, true)
	StaminaLedger.spend(player, 10000)
	stamina.follow_status(player.stamina)
	StaminaLedger.settle(player, _rules, 3, true, true)
	assert_int(stamina.stamina).is_equal(player.stamina)
	assert_bool(stamina.is_sprinting()).is_equal(player.sprinting)


func test_off_the_network_a_self_status_is_taken_as_it_is() -> void:
	var stamina := PredictedStamina.new(_rules)
	stamina.follow_status(12345)
	assert_int(stamina.stamina).is_equal(12345)
	assert_bool(stamina.follows_claims()).is_false()


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
