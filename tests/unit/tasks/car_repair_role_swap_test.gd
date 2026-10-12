extends GdUnitTestSuite
## The car repair's role-swap check (the car repair ADR's §7, R3; no condition reads a role): the
## same seed and the same commands with two players' forced roles swapped emit identical task
## event streams (LiftChanged, PartNeeded, TaskState, TaskProgress, Died) and identical Rejected
## streams, reasons included, for the two swapped players, from the same refused intents at the
## panel, the car and a bin. The leak test checks only who receives the events; a panel that
## refused the dissidents would still send everyone the same events while telling them a role.
## (The chaos run's swapped check never deals car repair, RD13.)
## Planted once in CarRepair.use_problem ("the panel refuses a dissident": `unavailable` when the
## actor's role is dissident and the station is the panel): both tests failed; reverted (#807).

const P1 := 1
const P2 := 2
const P3 := 3
const TASK_EVENTS: Array[StringName] = [
	&"LiftChanged", &"PartNeeded", &"TaskState", &"TaskProgress", &"Died"
]
const AWAY := Vector3(10, 0, 20)


func test_swapping_two_roles_changes_no_task_event_and_no_refusal() -> void:
	var first := _played({P1: &"crew", P2: &"dissident"})
	var second := _played({P1: &"dissident", P2: &"crew"})
	assert_str(first.state.player(P2).role).is_equal("dissident")
	assert_str(second.state.player(P2).role).is_equal("crew")
	for peer: int in [P1, P2, P3]:
		var stream := FixtureCarRepairModes.described(first, peer, TASK_EVENTS)
		assert_array(FixtureCarRepairModes.described(second, peer, TASK_EVENTS)).is_equal(stream)
	var names := FixtureCarRepairModes.stream(first, P1, TASK_EVENTS)
	assert_array(names).contains([&"PartNeeded", &"LiftChanged", &"Died"])
	for peer: int in [P1, P2]:
		assert_array(FixtureModes.rejections(second, peer)).is_equal(
			FixtureModes.rejections(first, peer)
		)
	assert_array(FixtureModes.rejections(first, P2)).is_equal(
		[&"unavailable", &"out_of_reach", &"busy", &"too_soon", &"out_of_reach"]
	)
	assert_array(FixtureModes.rejections(first, P1)).is_equal([&"busy"])


func test_a_dissident_holds_the_lift_and_takes_a_part() -> void:
	var game := _played({P1: &"dissident", P2: &"crew"})
	assert_array(_ups(game)).is_equal([true, false])
	var task_state := FixtureCarRepairModes.state_of(game)
	var held := game.state.items.get(game.state.players[P2].held_item) as ItemState
	assert_object(held).is_not_null()
	assert_str(String(held.kind.id)).is_equal(
		String(FixtureCarRepairModes.type_of(game.mode).parts[0].id)
	)
	assert_int(game.state.players[P3].life).is_equal(PlayerState.Life.DEAD)
	assert_int(task_state.held_since).is_equal(-1)


## A round of winning() (roles dealt, one dissident) with P1, P2 and P3 and `forced` roles: P2 tries
## the car before it is up and the panel from afar; P1 holds the lift; P2 and P1 press the held
## panel; P2 takes a part from the first bin, again too soon, and tries the second from afar; P3
## stands under the raised car and P1 lets go.
func _played(forced: Dictionary[int, StringName]) -> Match:
	var game := FixtureCarRepairModes.in_round(
		FixtureCarRepairModes.winning(), [P1, P2, P3], {}, {}, 7, forced
	)
	var task_state := FixtureCarRepairModes.state_of(game)
	FixtureCarRepairModes.use(game, P2, task_state.car, 1)
	FixtureItemModes.stand(game, P2, AWAY)
	FixtureStationModes.interact(game, P2, task_state.panel, 2)
	FixtureCarRepairModes.hold(game, P1, 1)
	FixtureModes.run_ticks(game, 2)
	FixtureCarRepairModes.hold(game, P2, 3)
	FixtureStationModes.interact(game, P1, task_state.panel, 2)
	FixtureCarRepairModes.use(game, P2, task_state.bins[0], 4)
	FixtureModes.run_ticks(game, 1)
	FixtureCarRepairModes.use(game, P2, task_state.bins[0], 5)
	FixtureItemModes.stand(game, P2, AWAY)
	FixtureStationModes.interact(game, P2, task_state.bins[1], 6)
	FixtureItemModes.stand(game, P3, FixtureCarRepairModes.under())
	FixtureModes.run_ticks(game, FixtureCarRepairModes.RISE_TICKS)
	FixtureCombatModes.stop_raise(game, P1, 3)
	FixtureModes.run_ticks(game, 2)
	return game


## The `up` of each LiftChanged P3 received, in order.
func _ups(game: Match) -> Array[bool]:
	var found: Array[bool] = []
	for event: MatchEvent in game.view_of(P3).events_named(&"LiftChanged"):
		found.append((event as LiftChangedEvent).up)
	return found
