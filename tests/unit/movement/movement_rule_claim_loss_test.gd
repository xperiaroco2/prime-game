extends GdUnitTestSuite
## A movement claim lost on the LATEST lane (#429, from PR #428's "Needs the engineer" item 2):
## the two behaviours of ARCHITECTURE §7.1 "Lost claims" an honest player meets over a lossy link,
## and what the core rules see once the client makes the claims that matter RELIABLE (the
## engineer's A1 + B3 on PR #434): the last claim again, on MoveClaimReliable, right before a
## player action; an epoch's first claim on the twin, which a lossy link delays but never loses.
## The host hands the twin to core/ as a plain MoveClaim, so these tests send MoveClaims; the
## rules do not change. Until the client change, these two tests had the lost claim never arrive
## and failed (PR #434's first commit, "test(core): reproduce the two lost-claim behaviours of
## #429"): the scenarios gained the twin, the assertions stayed.
## A lost claim is a host tick without it; every other claim is FixtureMoves' honest client in
## step with the host.

const P1 := 1
const EAST := Vector3(1, 0, 0)
## Under the walk speed (0.225 m per tick) and its slack.
const WALK_STEP := 0.2


func test_an_honest_pick_up_after_a_lost_claim_is_not_refused() -> void:
	# The player walks ten ticks east towards a tool lying 3.9 m away and stops 1.9 m from it,
	# within the 2 m reach. The LATEST claim of the last step is lost, so the host has it 2.1 m
	# away, until the client resends that claim, as sent, right before the PickUp (A1).
	var game := FixtureItemModes.in_round(FixtureItemModes.basic(), [P1])
	var player := game.state.player(P1)
	var start := player.position
	var item := FixtureItemModes.lay(game, &"tool", start + EAST * 3.9)
	var seen := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.steps(game, P1, 9, EAST * WALK_STEP, {"moving": true})
	var lost_tick := game.ticked_through() + 1
	FixtureModes.run_ticks(game, 1)
	var last := start + EAST * WALK_STEP * 10
	FixtureMoves.claim(game, P1, last, {"moving": true, "client_tick": lost_tick})
	FixtureItemModes.pick_up(game, P1, item)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(item.where).is_equal(ItemState.Where.HAND)
	assert_vector(player.position).is_equal_approx(last, Vector3.ONE * 1e-4)


func test_an_epochs_lost_first_claim_does_not_correct_the_next_one() -> void:
	# Right after the placement the player walks east. Its first claim of the epoch goes on the
	# twin (B3): a lossy link delays it, so it arrives a host tick late, together with the second
	# claim, two ticks of walking from the spot. The second then counts its real one-tick span.
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	var spot := player.position
	var seen := FixtureMoves.corrections(game, P1).size()
	var first_tick := game.ticked_through() + 1
	FixtureModes.run_ticks(game, 1)
	var first := {"moving": true, "client_tick": first_tick}
	FixtureMoves.claim(game, P1, spot + EAST * WALK_STEP, first)
	FixtureMoves.claim(game, P1, spot + EAST * WALK_STEP * 2, {"moving": true})
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_vector(player.position).is_equal_approx(spot + EAST * WALK_STEP * 2, Vector3.ONE * 1e-4)


func test_a_claim_given_again_after_it_was_applied_changes_nothing() -> void:
	# The LATEST claim arrived after all, and its resend on the twin follows: the copy's tick does
	# not rise, so the host drops it in silence (§7.1), whatever the player did since.
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	var spot := player.position
	FixtureMoves.steps(game, P1, 3, EAST * WALK_STEP, {"moving": true})
	var tick := game.ticked_through()
	var at := player.position
	var stamina := player.stamina
	var epoch := player.epoch
	var claim_tick := player.claim_tick
	var seen := FixtureMoves.corrections(game, P1).size()
	var events := game.emitted().size()
	FixtureMoves.claim(game, P1, at, {"moving": true, "client_tick": tick})
	FixtureMoves.claim(game, P1, spot, {"client_tick": tick - 1})
	assert_int(game.emitted().size()).is_equal(events)
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_vector(player.position).is_equal(at)
	assert_int(player.stamina).is_equal(stamina)
	assert_int(player.epoch).is_equal(epoch)
	assert_int(player.claim_tick).is_equal(claim_tick)
