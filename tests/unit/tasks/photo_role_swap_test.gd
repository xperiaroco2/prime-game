extends GdUnitTestSuite
## The photo task's role-swap check (the photo ADR §8, PD13: a load and a shot read no role): the
## same seed and the same commands with two players' forced roles swapped emit identical FilmLoaded,
## ShotTaken, TaskState and TaskProgress streams. The leak test checks only who receives them; a
## frame that skipped the dissidents would still send everyone the same events.
## Planted once in PhotoTask._shoot ("the frame skips dissidents": `continue` for a player whose
## role is dissident, so it neither counts nor gets a row): both tests failed; reverted (#781).

const P1 := 1
const P2 := 2
const P3 := 3
const TASK_EVENTS: Array[StringName] = [&"FilmLoaded", &"ShotTaken", &"TaskState", &"TaskProgress"]


func test_swapping_two_roles_changes_no_task_event() -> void:
	var first := _played({P1: &"crew", P2: &"dissident"})
	var second := _played({P1: &"dissident", P2: &"crew"})
	assert_str(first.state.player(P2).role).is_equal("dissident")
	assert_str(second.state.player(P2).role).is_equal("crew")
	var stream := _task_stream(first)
	assert_int(stream.size()).is_greater(2)
	assert_array(_task_stream(second)).is_equal(stream)


func test_a_dissident_in_the_frame_counts() -> void:
	var game := _played({P1: &"crew", P2: &"dissident"})
	var shots := FixturePhotoModes.state_of(game).shots
	assert_array(Array(shots[0].subjects)).is_equal([P2])
	assert_array(Array(shots[1].subjects)).is_equal([P1])


## A round of winning() (roles dealt, `dissidents` 1) with P1, P2 and P3 and `forced` roles: P1
## loads the dealt film and shoots P2 in the frame; P2 takes P1's place and shoots P1.
func _played(forced: Dictionary[int, StringName]) -> Match:
	var game := FixturePhotoModes.in_round(
		FixturePhotoModes.winning(), [P1, P2, P3], {}, null, forced
	)
	var camera := FixturePhotoModes.camera_of(game)
	FixturePhotoModes.take(game, P1, FixturePhotoModes.dealt_film(game))
	FixturePhotoModes.use(game, P1, camera)
	FixtureItemModes.stand(game, P2, FixturePhotoModes.IN_FRAME)
	FixtureItemModes.stand(game, P3, Vector3(30, 0, 0))
	FixturePhotoModes.use(game, P1, camera)
	FixtureItemModes.stand(game, P1, FixturePhotoModes.IN_FRAME)
	FixturePhotoModes.use(game, P2, camera)
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
