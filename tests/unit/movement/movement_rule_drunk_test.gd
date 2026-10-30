extends GdUnitTestSuite
## MovementRule and the drunk walk (#1391; ARCHITECTURE §7.1.20 "The walk drift needs no
## allowance"): a guard, green before the drift was built, as the host never reads
## PlayerState.drunk. A walk and a sprint turned every tick by the drift (DrunkFeel.drifted at the
## shipped tuning's largest angle, either way and wandering) keep their length, so the host's
## travel check accepts each step with no Correction; the same drunk player claiming 1.5 times the
## walk is corrected: being drunk gives no allowance, so a cheater gains nothing by it. Numbers per
## tick: FixtureMoves (walk 0.225 m, sprint 0.35 m, slack 0.05 m).

const TUNING := preload("res://client/player/player_tuning.tres")
const P1 := 1
## The highest drunk value below the base mode's drunk_too_much_at (90).
const DRUNK := 89
const WALK_M := 0.225
const SPRINT_M := 0.35
const STEPS := 40


func test_a_drifting_walk_and_sprint_at_drunk_89_are_never_corrected() -> void:
	var game := FixtureMoves.in_round([P1])
	game.state.player(P1).drunk = DRUNK
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	var widest := DrunkFeel.max_drift_angle(TUNING)
	assert_float(widest).is_greater(0.0)
	var keys := Vector3(0, 0, -1)
	for i: int in STEPS:
		# The widest turn either way, then the wander itself at full strength.
		var angle := widest if i % 3 == 0 else -widest
		if i % 3 == 2:
			angle = DrunkFeel.drift_angle(1.0, i * 0.05, P1, TUNING)
		var walk := DrunkFeel.drifted(keys * WALK_M, angle)
		FixtureMoves.step(game, P1, walk, {"moving": true})
	for i: int in STEPS:
		var angle := widest if i % 2 == 0 else -widest
		FixtureMoves.step(
			game, P1, DrunkFeel.drifted(keys * SPRINT_M, angle), FixtureMoves.sprinting()
		)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)


func test_a_drunk_player_claiming_more_than_the_walk_is_corrected() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	player.drunk = DRUNK
	FixtureMoves.step(game, P1, Vector3.ZERO)
	var seen := FixtureMoves.corrections(game, P1).size()
	var at := player.position
	var turned := DrunkFeel.drifted(
		Vector3(0, 0, -1) * WALK_M * 1.5, DrunkFeel.max_drift_angle(TUNING)
	)
	FixtureMoves.step(game, P1, turned, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_vector(player.position).is_equal(at)
