extends GdUnitTestSuite
## MovementRule.claim_age (ZE10 of the zone task ADR, ARCHITECTURE §7.1.5): how many host ticks old
## a player's last accepted claim is, or -1 when its position is no claim of its current epoch.
## Driven by FixtureMoves' honest client in step with the host.

const P1 := 1
const P2 := 2
const EAST := Vector3(1, 0, 0)


func test_it_is_minus_one_before_the_first_claim_of_the_round() -> void:
	var game := FixtureMoves.in_round([P1])
	var now := game.ticked_through() + 1
	assert_int(MovementRule.claim_age(game.state, P1, now)).is_equal(-1)
	assert_int(MovementRule.claim_age(game.state, 99, now)).is_equal(-1)


func test_it_is_zero_in_the_claims_tick_and_grows_by_one_a_tick() -> void:
	var game := FixtureMoves.in_round([P1])
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var accepted := game.ticked_through()
	assert_int(MovementRule.claim_age(game.state, P1, accepted)).is_equal(0)
	assert_int(MovementRule.claim_age(game.state, P1, accepted + 1)).is_equal(1)
	assert_int(MovementRule.claim_age(game.state, P1, accepted + 10)).is_equal(10)
	FixtureMoves.step(game, P1, EAST * 0.2)
	assert_int(MovementRule.claim_age(game.state, P1, game.ticked_through())).is_equal(0)


func test_a_refused_claim_does_not_renew_it() -> void:
	var game := FixtureMoves.in_round([P1])
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var accepted := game.ticked_through()
	FixtureModes.run_ticks(game, 3)
	var corrected := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, EAST * 30)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(corrected + 1)
	var now := game.ticked_through()
	assert_int(MovementRule.claim_age(game.state, P1, now)).is_equal(now - accepted)


func test_a_placement_makes_it_minus_one_until_the_epochs_first_claim() -> void:
	var game := FixtureMoves.in_round([P1, P2])
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = game.ticked_through() + 1
	LifeRules.knock_down(ctx, P1)
	assert_int(MovementRule.claim_age(game.state, P1, ctx.tick)).is_equal(-1)
	FixtureModes.run_ticks(game, 2)
	assert_int(MovementRule.claim_age(game.state, P1, game.ticked_through())).is_equal(-1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	assert_int(MovementRule.claim_age(game.state, P1, game.ticked_through())).is_equal(0)


func test_a_refused_or_malformed_first_claim_after_a_placement_leaves_it_minus_one() -> void:
	# The first claim of a new epoch resets the record (_after_placement) before it is read or
	# checked: a refused one bumps the epoch with its Correction, but the position is still the
	# host's placement, so no age starts (the netcode review of #647).
	for refused: Dictionary in [{"far": true}, {"client_tick": "late"}]:
		var game := FixtureMoves.in_round([P1, P2])
		FixtureMoves.step(game, P1, Vector3.ZERO)
		var ctx := MatchContext.new(game)
		ctx.state = game.state
		ctx.mode = game.mode
		ctx.world = FlatWorldQuery.new()
		ctx.tick = game.ticked_through() + 1
		LifeRules.knock_down(ctx, P1)
		var corrected := FixtureMoves.corrections(game, P1).size()
		if refused.has("far"):
			FixtureMoves.step(game, P1, EAST * 30)
		else:
			FixtureMoves.step(game, P1, Vector3.ZERO, refused)
		assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(corrected + 1)
		FixtureModes.run_ticks(game, 1)
		assert_int(MovementRule.claim_age(game.state, P1, game.ticked_through())).is_equal(-1)
		FixtureMoves.step(game, P1, Vector3.ZERO)
		assert_int(MovementRule.claim_age(game.state, P1, game.ticked_through())).is_equal(0)


func test_credit_gain_is_minus_one_before_a_claim_and_stays_0_for_an_honest_client() -> void:
	var game := FixtureMoves.in_round([P1])
	assert_int(MovementRule.credit_gain(game.state, P1, game.ticked_through() + 1)).is_equal(-1)
	FixtureMoves.steps(game, P1, 5, EAST * 0.2)
	assert_int(MovementRule.credit_gain(game.state, P1, game.ticked_through())).is_equal(0)
	# Lost claims: the silent ticks count until the next claim covers them.
	FixtureModes.run_ticks(game, 3)
	assert_int(MovementRule.credit_gain(game.state, P1, game.ticked_through())).is_equal(3)
	FixtureMoves.step(game, P1, EAST * 0.2)
	assert_int(MovementRule.credit_gain(game.state, P1, game.ticked_through())).is_equal(0)


func test_credit_gain_counts_what_a_slow_claimer_stores() -> void:
	# A claim every 10 host ticks that covers one client tick keeps claim_age under 10 but stores 9
	# ticks of credit each time (the netcode review of #647).
	var game := FixtureMoves.in_round([P1])
	FixtureMoves.step(game, P1, Vector3.ZERO)
	for i in 3:
		FixtureModes.run_ticks(game, 9)
		_claim_next(game, P1, 1)
		var now := game.ticked_through()
		assert_int(MovementRule.claim_age(game.state, P1, now)).is_equal(0)
		assert_int(MovementRule.credit_gain(game.state, P1, now)).is_equal(9 * (i + 1))


func test_credit_spent_lowers_the_least_and_stored_again_counts() -> void:
	# Credit stored and then spent in one claim is no gain from the new least; storing it again is.
	var game := FixtureMoves.in_round([P1])
	FixtureMoves.step(game, P1, Vector3.ZERO)
	for i in 3:
		FixtureModes.run_ticks(game, 9)
		_claim_next(game, P1, 1)
	assert_int(MovementRule.credit_gain(game.state, P1, game.ticked_through())).is_equal(27)
	var corrected := FixtureMoves.corrections(game, P1).size()
	_claim_next(game, P1, 30)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(corrected)
	assert_int(MovementRule.credit_gain(game.state, P1, game.ticked_through())).is_equal(0)
	for i in 5:
		_claim_next(game, P1, 1)
	assert_int(MovementRule.credit_gain(game.state, P1, game.ticked_through())).is_equal(0)
	FixtureModes.run_ticks(game, 9)
	_claim_next(game, P1, 1)
	assert_int(MovementRule.credit_gain(game.state, P1, game.ticked_through())).is_equal(9)


func test_a_placement_makes_credit_gain_minus_one_until_the_epochs_first_claim() -> void:
	var game := FixtureMoves.in_round([P1, P2])
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureModes.run_ticks(game, 9)
	_claim_next(game, P1, 1)
	assert_int(MovementRule.credit_gain(game.state, P1, game.ticked_through())).is_equal(9)
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = game.ticked_through() + 1
	LifeRules.knock_down(ctx, P1)
	assert_int(MovementRule.credit_gain(game.state, P1, ctx.tick)).is_equal(-1)
	FixtureMoves.step(game, P1, Vector3.ZERO)
	assert_int(MovementRule.credit_gain(game.state, P1, game.ticked_through())).is_equal(0)


## A claim where the host has `peer`, `covered` client ticks after its last accepted one, applied
## on the next host tick.
func _claim_next(game: Match, peer: int, covered: int) -> void:
	var player := game.state.player(peer)
	FixtureMoves.claim(game, peer, player.position, {"client_tick": player.claim_tick + covered})
	FixtureModes.run_ticks(game, 1)
