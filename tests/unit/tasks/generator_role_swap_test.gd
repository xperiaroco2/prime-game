extends GdUnitTestSuite
## The Generator's role-swap check (the Generator ADR's testing part; GE2: a use reads no role):
## the same seed and the same commands with two players' forced roles swapped emit an identical
## stream of task events. The leak test checks only who receives the events; a Generator whose
## button refused the dissidents would still send everyone the same events while telling them a
## role.
## Planted once in Generator.use_problem ("the button refuses a dissident": `unavailable` when the
## actor's role is dissident and the station is the generator):
## test_swapping_two_roles_changes_no_task_event and test_a_lone_dissident_charges_the_generator
## failed; reverted (#797).

const P1 := 1
const P2 := 2
const P3 := 3
const TASK_EVENTS: Array[StringName] = [
	&"SwitchChanged", &"ButtonPressed", &"ZoneProgress", &"TaskState", &"TaskProgress"
]


func test_swapping_two_roles_changes_no_task_event() -> void:
	var first := _played({P1: &"crew", P2: &"dissident"})
	var second := _played({P1: &"dissident", P2: &"crew"})
	assert_str(first.state.player(P2).role).is_equal("dissident")
	assert_str(second.state.player(P2).role).is_equal("crew")
	var stream := _task_stream(first)
	assert_int(stream.size()).is_greater(6)
	assert_array(_task_stream(second)).is_equal(stream)


func test_a_lone_dissident_charges_the_generator() -> void:
	var game := _played({P1: &"crew", P2: &"dissident"})
	assert_bool(FixtureGeneratorModes.state_of(game).done).is_true()


## A round of winning(2) (roles dealt, `dissidents` 1) with P1, P2 and P3 and `forced` roles:
## P1 turns one switch on and off, P2 alone turns both on, presses twice (start, stop), then
## presses again and charges it full; P3 never acts.
func _played(forced: Dictionary[int, StringName]) -> Match:
	var game := FixtureGeneratorModes.in_round(
		FixtureGeneratorModes.winning(2), [P1, P2, P3], {}, {}, 7, forced
	)
	var button := FixtureGeneratorModes.button_of(game)
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.switch_of(game, 0))
	FixtureGeneratorModes.use(game, P1, FixtureGeneratorModes.switch_of(game, 0), 1)
	FixtureGeneratorModes.switch_all_on(game, P2)
	FixtureGeneratorModes.use(game, P2, button, 1)
	FixtureModes.run_ticks(game, 3)
	FixtureGeneratorModes.use(game, P2, button, 2)
	FixtureModes.run_ticks(game, 6)
	FixtureGeneratorModes.use(game, P2, button, 3)
	FixtureModes.run_ticks(game, FixtureGeneratorModes.NEEDED)
	return game


## The task events that P3 received, as plain data, in order.
func _task_stream(game: Match) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(P3).events:
		if event.event_name() in TASK_EVENTS:
			var entry := event.to_dict()
			entry["name"] = event.event_name()
			found.append(entry)
	return found
