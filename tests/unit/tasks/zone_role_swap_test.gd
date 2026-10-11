extends GdUnitTestSuite
## The zone task's role-swap check (§7 of the zone task ADR, ZD3): counting is role-blind, so the
## same seed and the same claims with two players' forced roles swapped emit an identical stream of
## ZoneProgress, TaskState and TaskProgress. The leak test checks only who receives the events; a
## ZoneTask that counted the crew alone would still send everyone the same events while telling
## them a role. Planted once in ZoneTask._anyone_inside ("counts the crew only": skip a player
## whose role is not crew), test_swapping_two_roles_changes_no_task_event and
## test_a_lone_dissident_advances_a_zone failed; reverted (#647).

const P1 := 1
const P2 := 2
const P3 := 3
const A := Vector3(0, 0, 20)
const B := Vector3(3, 0, 20)
const SOUTH := Vector3(0, 0, -1)


func test_swapping_two_roles_changes_no_task_event() -> void:
	var first := _played({P1: &"crew", P2: &"dissident"})
	var second := _played({P1: &"dissident", P2: &"crew"})
	assert_str(first.state.player(P2).role).is_equal("dissident")
	assert_str(second.state.player(P2).role).is_equal("crew")
	var stream := _task_stream(first)
	assert_int(stream.size()).is_greater(4)
	assert_array(_task_stream(second)).is_equal(stream)
	assert_int(FixtureZoneModes.state_of(first).done_count()).is_equal(1)


func test_a_lone_dissident_advances_a_zone() -> void:
	var game := _played({P1: &"crew", P2: &"dissident"})
	assert_bool(FixtureZoneModes.state_of(game).done[0]).is_true()


## A round of two zones (winning(): roles dealt, `dissidents` 1) with P1, P2 and P3 and `forced`
## roles: P2 works zone A alone, steps out and back, and finishes it; P1 stands in zone B for a
## while and leaves; P3 never claims.
func _played(forced: Dictionary[int, StringName]) -> Match:
	var game := FixtureZoneModes.in_round(
		FixtureZoneModes.winning(2), [P1, P2, P3], {}, {}, 7, forced
	)
	FixtureZoneModes.put(game, P2, A + SOUTH * 1.4)
	FixtureZoneModes.put(game, P1, B)
	FixtureZoneModes.hold(game, [P1, P2], 8)
	FixtureMoves.claim(game, P1, B)
	FixtureMoves.step(game, P2, SOUTH * 0.2)
	FixtureZoneModes.walk(game, P1, B + Vector3(0, 0, -2), [P2])
	FixtureMoves.step(game, P2, -SOUTH * 0.2)
	FixtureZoneModes.hold(game, [P1, P2], FixtureZoneModes.NEEDED)
	return game


## The ZoneProgress, TaskState and TaskProgress that P3 received, as plain data, in order.
func _task_stream(game: Match) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(P3).events:
		if event.event_name() in [&"ZoneProgress", &"TaskState", &"TaskProgress"]:
			var entry := event.to_dict()
			entry["name"] = event.event_name()
			found.append(entry)
	return found
