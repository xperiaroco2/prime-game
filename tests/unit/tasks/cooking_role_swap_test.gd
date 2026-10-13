extends GdUnitTestSuite
## Cooking's role-swap check (the cooking ADR §7, C4: a take, a put, the grill and a place read no
## role): the same seed and the same commands with two players' forced roles swapped emit identical
## OrderPosted, HerbsDealt, IngredientPlaced, GrillLoaded, ItemChanged, ItemVanished, TaskState and
## TaskProgress streams. The leak test checks only who receives them; a place that refused the
## dissidents would still send everyone the same events.
## Planted once in Cooking.use_problem, before a place's problem ("a place refuses dissidents":
## `unavailable` for an actor whose role is dissident): both tests failed; reverted (#773).

const P1 := 1
const P2 := 2
const P3 := 3
const TASK_EVENTS: Array[StringName] = [
	&"OrderPosted",
	&"HerbsDealt",
	&"IngredientPlaced",
	&"GrillLoaded",
	&"ItemChanged",
	&"ItemVanished",
	&"TaskState",
	&"TaskProgress",
]
## Long enough for the fixture's VANISH (60 s) to pass inside the round.
const MINUTES := 5


func test_swapping_two_roles_changes_no_task_event() -> void:
	var first := _played({P1: &"crew", P2: &"dissident"})
	var second := _played({P1: &"dissident", P2: &"crew"})
	assert_str(first.state.player(P2).role).is_equal("dissident")
	assert_str(second.state.player(P2).role).is_equal("crew")
	var stream := _task_stream(first)
	var names: Array[StringName] = []
	for entry: Dictionary in stream:
		if not names.has(entry["name"]):
			names.append(entry["name"])
	# Every event of the check is in the stream, so the comparison covers each.
	for event_name: StringName in TASK_EVENTS:
		assert_array(names).contains([event_name])
	assert_array(_task_stream(second)).is_equal(stream)


func test_a_dissident_s_right_bun_is_locked_on_its_place() -> void:
	var game := _played({P1: &"crew", P2: &"dissident"})
	var task_state := FixtureCookingModes.state_of(game)
	assert_bool(task_state.orders[0].done).is_true()
	assert_int(task_state.orders[1].bun_item).is_not_equal(-1)
	assert_bool(task_state.orders[1].done).is_false()
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	# The round runs on: one burger of two is done, the clock has 5 minutes.
	assert_str(String(game.phase_id())).is_equal("round")


## A round of winning(2) (roles dealt, `dissidents` 1) with P1, P2 and P3 and `forced` roles: P1
## cooks order 0; P2 puts order 1's bun and then the other bun on place 1, loads a raw patty and
## lets it burn; then the round runs on until the wrong bun has vanished. Burger 1 stays unfinished
## (every task done would end the round).
func _played(forced: Dictionary[int, StringName]) -> Match:
	var game := FixtureCookingModes.in_round(
		FixtureCookingModes.winning(2), [P1, P2, P3], {}, 7, {&"match_duration": MINUTES}, forced
	)
	FixtureItemModes.stand(game, P3, Vector3(-30, 0, 0))
	FixtureCookingModes.cook(game, P1, 0)
	var order := FixtureCookingModes.state_of(game).orders[1]
	var place := FixtureCookingModes.place_of(game, 1)
	FixtureCookingModes.take(game, P2, order.bun.id)
	FixtureCookingModes.use(game, P2, place)
	FixtureModes.run_ticks(game, 1)
	FixtureCookingModes.take(game, P2, _other_bun(game, order).id)
	FixtureCookingModes.use(game, P2, place)
	FixtureModes.run_ticks(game, 1)
	FixtureCookingModes.take(game, P2, order.raw_patty.id)
	FixtureCookingModes.use(game, P2, FixtureCookingModes.grill_of(game))
	var type := FixtureCookingModes.type_of(game.mode)
	FixtureModes.run_ticks(game, type.burnt_ticks() + 1)
	FixtureModes.run_ticks(game, Ticks.from_seconds(FixtureCookingModes.VANISH) + 1)
	return game


func _other_bun(game: Match, order: Cooking.Order) -> ItemKind:
	for bun: ItemKind in FixtureCookingModes.type_of(game.mode).buns:
		if bun != order.bun:
			return bun
	return null


## The task events that P3 received, as plain data, in order.
func _task_stream(game: Match) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(P3).events:
		if event.event_name() in TASK_EVENTS:
			var entry := event.to_dict()
			entry["name"] = event.event_name()
			found.append(entry)
	return found
