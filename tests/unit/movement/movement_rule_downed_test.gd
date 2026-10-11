extends GdUnitTestSuite
## MovementRule for a knocked-down sender (ARCHITECTURE §7.1; the knockdown rework's KE4, its §9
## Movement tests): it cannot move, so the host takes its claim's facing only, sends it no
## Correction, and settles its ticks as regenerating; a malformed, a negative-tick and a past-credit
## claim are dropped with no Correction and no facing taken; a stale claim is dropped as before; a
## taken claim advances claim_tick and spends credit as an accepted one does. Driven by a seeded
## round of FixtureCombatModes.basic(): P1's knife downs P2 (two hits, the cooldown apart), so the
## knockdown is the real one, a placement with its own epoch.

const P1 := 1
const P2 := 2
const P3 := 3
const NORTH := Vector3(0, 0, 1)
const EAST := Vector3(1, 0, 0)
const WEST := Vector3(-1, 0, 0)
## Where P2 lies once downed.
const LIES := Vector3(0, 0, 1)


func test_a_claim_of_a_far_place_moves_nothing_and_sends_no_correction() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	var seen := FixtureMoves.corrections(game, P2).size()
	# A teleport 30 m away, a run at sprint speed and a jump: none moves it, none is corrected.
	FixtureMoves.claim(game, P2, LIES + EAST * 30, {"velocity": EAST * 7})
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.steps(game, P2, 5, EAST * 0.35, FixtureMoves.sprinting())
	FixtureMoves.step(game, P2, Vector3(0, 1, 0), FixtureMoves.jumped(game, P2))
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(seen)
	assert_vector(downed.position).is_equal(LIES)
	assert_vector(downed.velocity).is_equal(Vector3.ZERO)
	assert_bool(downed.sprinting).is_false()
	assert_bool(downed.sprint_held).is_false()
	assert_bool(downed.moving).is_false()
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	assert_array(Array(game.diagnostics)).is_empty()


func test_its_facing_is_taken_as_a_unit_vector() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	FixtureMoves.claim(game, P2, LIES + EAST * 3, {"facing": EAST * 2})
	FixtureModes.run_ticks(game, 1)
	assert_vector(downed.facing).is_equal_approx(EAST, Vector3.ONE * 1e-6)
	FixtureMoves.claim(game, P2, LIES, {"facing": WEST})
	FixtureModes.run_ticks(game, 1)
	assert_vector(downed.facing).is_equal_approx(WEST, Vector3.ONE * 1e-6)
	assert_vector(downed.position).is_equal(LIES)


func test_its_ticks_regenerate_stamina_holding_sprint_or_not() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	downed.stamina = 0
	FixtureMoves.step(game, P2, Vector3.ZERO)
	var stamina_before := downed.stamina
	FixtureMoves.steps(game, P2, 20, EAST * 0.05, FixtureMoves.sprinting())
	# 750 thousandths a tick, as for a living player who does not sprint.
	assert_int(downed.stamina).is_equal(stamina_before + 20 * 750)
	assert_bool(downed.sprinting).is_false()


func test_a_malformed_claim_is_dropped_with_no_correction_and_no_facing_taken() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	FixtureMoves.step(game, P2, Vector3.ZERO, {"facing": EAST})
	var seen := FixtureMoves.corrections(game, P2).size()
	var tick := downed.claim_tick
	for bad: Dictionary in [
		{"position": Vector3(INF, 0, 0)},
		{"velocity": Vector3(NAN, 0, 0)},
		{"jumps": -1},
		{"client_tick": 2.5},
	]:
		var fields := {"facing": WEST}
		fields.merge(bad, true)
		FixtureMoves.claim(game, P2, LIES, fields)
		FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(seen)
	assert_vector(downed.facing).is_equal_approx(EAST, Vector3.ONE * 1e-6)
	assert_int(downed.claim_tick).is_equal(tick)


func test_a_negative_client_tick_is_dropped_with_no_correction_and_no_facing_taken() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	var seen := FixtureMoves.corrections(game, P2).size()
	var facing := downed.facing
	# The first claim after the knockdown has no baseline to fall below: a living player's would be
	# corrected.
	FixtureMoves.claim(game, P2, LIES, {"client_tick": -1, "facing": WEST})
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(seen)
	assert_vector(downed.facing).is_equal(facing)
	assert_int(downed.claim_tick).is_equal(-1)


func test_a_stale_claim_is_dropped() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	var seen := FixtureMoves.corrections(game, P2).size()
	var facing := downed.facing
	# A walking claim it sent while living, still in flight: the old epoch.
	FixtureMoves.claim(game, P2, LIES + EAST, {"epoch": downed.epoch - 1, "facing": WEST})
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(seen)
	assert_vector(downed.facing).is_equal(facing)
	assert_int(downed.claim_tick).is_equal(-1)


func test_an_older_twin_sets_no_older_facing() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	# Stamina regenerating, so each tick's SelfStatus goes out (it is sent on a change only).
	downed.stamina = 0
	FixtureMoves.step(game, P2, Vector3.ZERO, {"facing": NORTH})
	var tick := downed.claim_tick
	FixtureMoves.claim(game, P2, LIES, {"client_tick": tick + 2, "facing": EAST})
	# Its older twin (MoveClaimReliable) or a reordered claim arrives after it.
	FixtureMoves.claim(game, P2, LIES, {"client_tick": tick + 1, "facing": WEST})
	FixtureModes.run_ticks(game, 1)
	assert_int(downed.claim_tick).is_equal(tick + 2)
	assert_vector(downed.facing).is_equal_approx(EAST, Vector3.ONE * 1e-6)
	# SelfStatus names the last claim taken.
	var statuses := FixtureMoves.statuses(game, P2)
	assert_int(statuses[statuses.size() - 1].claim_tick).is_equal(tick + 2)


func test_claims_ahead_of_the_host_spend_the_credit_and_meet_the_past_credit_drop() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	var seen := FixtureMoves.corrections(game, P2).size()
	# Within one host tick the client claims ever more ticks of its own: the lead of 10 is taken,
	# then the credit is spent and the next two are dropped, with no Correction and their facing
	# not taken.
	var tick := game.ticked_through()
	for i in 12:
		tick += 1
		var facing := EAST if i < 10 else WEST
		FixtureMoves.claim(game, P2, LIES + EAST * 0.2 * i, {"client_tick": tick, "facing": facing})
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(seen)
	assert_int(downed.claim_tick).is_equal(tick - 2)
	assert_vector(downed.facing).is_equal_approx(EAST, Vector3.ONE * 1e-6)
	assert_vector(downed.position).is_equal(LIES)
	# The past-credit drop rebased it: once the host's ticks give credit again, the next claim
	# is taken from a new baseline.
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.claim(game, P2, LIES, {"client_tick": tick + 1, "facing": WEST})
	FixtureModes.run_ticks(game, 1)
	assert_int(downed.claim_tick).is_equal(tick + 1)
	assert_vector(downed.facing).is_equal_approx(WEST, Vector3.ONE * 1e-6)
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(seen)


## A round of FixtureCombatModes.basic() with P1 armed at the origin, P2 at LIES and P3 out of the
## way; P1 hits P2 twice, the cooldown apart: P2 lies downed at LIES, with its knockdown's epoch and
## no claim of it yet.
func _downed() -> Match:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2, P3])
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, LIES)
	FixtureItemModes.stand(game, P3, Vector3(5, 0, 5))
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	assert_vector(game.state.player(P2).position).is_equal(LIES)
	return game
