extends GdUnitTestSuite
## MovementRule's per-tick masks (ARCHITECTURE §4.3, §7.1, #155): a MoveClaim's `sprint_ticks` and
## `moved_ticks` give each covered client tick its own flags (bit i: client tick client_tick - i),
## so a claim that the LATEST lane merged with older ones still says which of their ticks were
## sprinted. The host grants sprint speed for exactly those its ledger has the stamina for, and
## charges them. Numbers per tick: FixtureMoves (walk 0.225 m, sprint 0.35 m, slack 0.05 m; sprint
## costs 1000 thousandths, regeneration gives 750).

const P1 := 1
const EAST := Vector3(1, 0, 0)
## A merged claim's flags are its newest claim's: here a walk with movement input.
const WALKING := {"sprint": false, "moving": true}


func test_a_merged_claim_that_ends_a_sprint_passes_with_its_masks() -> void:
	# Two claims merged: a sprint tick, then the tick that lets go and walks (0.35 + 0.225 m).
	var game := _sprinting_player()
	var player := game.state.player(P1)
	FixtureModes.run_ticks(game, 1)
	var seen := FixtureMoves.corrections(game, P1).size()
	var stamina := player.stamina
	FixtureMoves.step(game, P1, EAST * 0.57, _merged(game, 2, 0b10, 0b11))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_equal(stamina - 1000 + 750)
	assert_bool(player.sprinting).is_false()


func test_the_same_merged_claim_without_its_sprint_bit_is_corrected() -> void:
	var game := _sprinting_player()
	var player := game.state.player(P1)
	FixtureModes.run_ticks(game, 1)
	var seen := FixtureMoves.corrections(game, P1).size()
	var at := player.position
	FixtureMoves.step(game, P1, EAST * 0.57, _merged(game, 2, 0b00, 0b11))
	var found := FixtureMoves.corrections(game, P1)
	assert_int(found.size()).is_equal(seen + 1)
	assert_vector(found[found.size() - 1].position).is_equal(at)


func test_a_three_claim_merge_at_a_sprints_end_passes_with_its_masks() -> void:
	# Two sprint ticks and the walk tick that ends the sprint: 0.35 + 0.35 + 0.225 = 0.925 m, past
	# the 0.4 + 0.225 + 0.225 m that one tick of sprint allowance would give.
	var game := _sprinting_player()
	var player := game.state.player(P1)
	FixtureModes.run_ticks(game, 2)
	var seen := FixtureMoves.corrections(game, P1).size()
	var stamina := player.stamina
	FixtureMoves.step(game, P1, EAST * 0.92, _merged(game, 3, 0b110, 0b111))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_equal(stamina - 2000 + 750)


func test_sprint_bits_the_stamina_does_not_cover_are_corrected() -> void:
	# One tick of stamina left: of three sprinted ticks the ledger grants the first only.
	var game := _sprinting_player()
	var player := game.state.player(P1)
	FixtureModes.run_ticks(game, 2)
	player.stamina = 1000
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, EAST * 1.0, _merged(game, 3, 0b111, 0b111))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.stamina).is_equal(1000)


func test_the_masks_and_not_the_flags_say_what_the_covered_ticks_paid() -> void:
	# Flags of a walk, masks of a sprint tick: the tick goes at sprint speed and is charged, so a
	# client alternating its flags gains nothing.
	var game := _sprinting_player()
	var player := game.state.player(P1)
	var seen := FixtureMoves.corrections(game, P1).size()
	var stamina := player.stamina
	FixtureMoves.step(game, P1, EAST * 0.35, _merged(game, 1, 0b1, 0b1))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_int(player.stamina).is_equal(stamina - 1000)


func test_bits_older_than_the_covered_ticks_count_for_nothing() -> void:
	# Every bit but the claim's own tick: the claim covers one tick, which walked.
	var game := _sprinting_player()
	var player := game.state.player(P1)
	var seen := FixtureMoves.corrections(game, P1).size()
	var stamina := player.stamina
	FixtureMoves.step(game, P1, EAST * 0.35, _merged(game, 1, 0xFFFFFFFE, 0xFFFFFFFE))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_int(player.stamina).is_equal(stamina)


func test_ticks_older_than_the_masks_take_the_oldest_bit() -> void:
	# 40 covered ticks, only bit 31 sprinted: ticks 31 to 39 back (nine) sprint, 31 walk, which
	# is 9 * 0.35 + 31 * 0.225 = 10.125 m, while one sprint tick would allow 9.175 m.
	var game := _sprinting_player()
	FixtureModes.run_ticks(game, 39)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.step(game, P1, EAST * 10.1, _merged(game, 40, 0x80000000, 0xFFFFFFFF))
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)


func test_a_mask_outside_the_wires_u32_is_corrected() -> void:
	for bad: Variant in [-1, 0x100000000, 1.0, true]:
		var game := _sprinting_player()
		var seen := FixtureMoves.corrections(game, P1).size()
		var fields := {"sprint_ticks": bad}
		fields.merge(FixtureMoves.sprinting())
		FixtureMoves.step(game, P1, EAST * 0.1, fields)
		(
			assert_int(FixtureMoves.corrections(game, P1).size())
			. override_failure_message(str(bad))
			. is_equal(seen + 1)
		)
		fields = {"moved_ticks": bad}
		fields.merge(FixtureMoves.sprinting())
		FixtureMoves.step(game, P1, EAST * 0.1, fields)
		(
			assert_int(FixtureMoves.corrections(game, P1).size())
			. override_failure_message(str(bad))
			. is_equal(seen + 2)
		)


## A round with P1 placed, one claim standing and one sprinting (in the sprint state, full of
## stamina but for that tick).
func _sprinting_player() -> Match:
	var game := FixtureMoves.in_round([P1])
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.step(game, P1, EAST * 0.35, FixtureMoves.sprinting())
	return game


## The fields of a claim covering `covered` client ticks since the last accepted one, with a
## walk's flags (the newest claim's) and the given masks.
func _merged(game: Match, covered: int, sprint_ticks: int, moved_ticks: int) -> Dictionary:
	var fields := {
		"client_tick": game.state.player(P1).claim_tick + covered,
		"sprint_ticks": sprint_ticks,
		"moved_ticks": moved_ticks,
	}
	fields.merge(WALKING)
	return fields
