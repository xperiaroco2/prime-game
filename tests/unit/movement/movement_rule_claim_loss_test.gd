extends GdUnitTestSuite
## A movement claim lost on the LATEST lane (#429, from PR #428's "Needs the engineer" item 2):
## the two behaviours of ARCHITECTURE §7.1 an honest player meets over a lossy link. Each test
## states what an honest player should see, and fails today: the fix is a rule change that the
## engineer chooses first (#429). A lost claim is a host tick without it; every other claim is
## FixtureMoves' honest client in step with the host.

const P1 := 1
const EAST := Vector3(1, 0, 0)
## Under the walk speed (0.225 m per tick) and its slack.
const WALK_STEP := 0.2


func test_an_honest_pick_up_after_a_lost_claim_is_not_refused() -> void:
	# The player walks ten ticks east towards a tool lying 3.9 m away and stops 1.9 m from it,
	# within the 2 m reach. The claim of the last step is lost, so the host has it 2.1 m away.
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1])
	var player := game.state.player(P1)
	var start := player.position
	var item := FixtureItemModes.lay(game, &"tool", start + EAST * 3.9)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.steps(game, P1, 9, EAST * WALK_STEP, {"moving": true})
	FixtureModes.run_ticks(game, 1)
	FixtureItemModes.pick_up(game, P1, item)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(item.where).is_equal(ItemState.Where.HAND)


func test_an_epochs_lost_first_claim_does_not_correct_the_next_one() -> void:
	# Right after the placement the player walks east. Its first claim of the epoch is lost, so
	# the second, two ticks of walking, is the epoch's fresh claim, which the host counts as one.
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	var spot := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.claim(game, P1, spot + EAST * WALK_STEP * 2, {"moving": true})
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_vector(player.position).is_equal_approx(spot + EAST * WALK_STEP * 2, Vector3.ONE * 1e-4)
