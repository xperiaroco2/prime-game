extends GdUnitTestSuite
## Swap (ARCHITECTURE §7.1, §9.4; vision revision 1, Two hands, V13): CarriesItem
## (`nothing_to_swap`) and HandNotTwoHanded (`two_handed`), then SwapHands, which exchanges the
## hand and belt items, either of which may be empty, and emits Swapped to everyone. Round accepts
## Swap from the living only. Only the hand item is used. Driven by commands through the fixture
## item mode with the swap (FixtureItemModes.swapping(basic()): a two-handed `package`, a
## one-handed `tool`) and the fixture raise mode; asserted on the events, view_of and the match
## state.

const P1 := 1
const P2 := 2
const P3 := 3
const HERE := Vector3(0, 0, 0)
const NORTH := Vector3(0, 0, 1)
const LIES := Vector3(0, 0, 1)
const RAISER := Vector3(1.5, 0, 1)


func test_a_lone_hand_item_goes_to_the_belt_and_back() -> void:
	var game := _game()
	var tool := _take(game, P1, &"tool")
	var player := game.state.player(P1)
	var seen := game.view_of(P2).events.size()
	FixtureItemModes.swap(game, P1)
	assert_int(player.held_item).is_equal(-1)
	assert_int(player.belt_item).is_equal(tool.id)
	assert_int(tool.where).is_equal(ItemState.Where.BELT)
	assert_int(tool.holder).is_equal(P1)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal([&"Swapped"])
	for peer: int in [P1, P2]:
		var swapped := game.view_of(peer).events_named(&"Swapped")
		assert_dict(swapped[0].to_dict()).is_equal({"peer": P1})
	FixtureItemModes.swap(game, P1)
	assert_int(player.held_item).is_equal(tool.id)
	assert_int(player.belt_item).is_equal(-1)
	assert_int(tool.where).is_equal(ItemState.Where.HAND)
	assert_array(game.view_of(P2).events_named(&"Swapped")).has_size(2)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_swap_exchanges_the_hand_and_belt_items() -> void:
	var game := _game()
	var first := _take(game, P1, &"tool")
	var second := _take(game, P1, &"tool")
	var player := game.state.player(P1)
	assert_int(player.belt_item).is_equal(first.id)
	assert_int(player.held_item).is_equal(second.id)
	FixtureItemModes.swap(game, P1)
	assert_int(player.held_item).is_equal(first.id)
	assert_int(player.belt_item).is_equal(second.id)
	assert_int(first.where).is_equal(ItemState.Where.HAND)
	assert_int(second.where).is_equal(ItemState.Where.BELT)
	assert_array(game.view_of(P1).events_named(&"ItemPlaced")).is_empty()


func test_a_two_handed_item_in_the_hand_refuses_the_swap() -> void:
	var game := _game()
	var tool := _take(game, P1, &"tool")
	var package := _take(game, P1, &"package")
	var seen := game.view_of(P2).events.size()
	FixtureItemModes.swap(game, P1, 4)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"two_handed"])
	var rejected := game.view_of(P1).events_named(&"Rejected")[0] as RejectedEvent
	assert_int(rejected.seq).is_equal(4)
	assert_int(game.state.player(P1).held_item).is_equal(package.id)
	assert_int(game.state.player(P1).belt_item).is_equal(tool.id)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_empty()


func test_with_both_slots_empty_there_is_nothing_to_swap() -> void:
	var game := _game()
	FixtureItemModes.swap(game, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_swap"])
	assert_array(game.view_of(P2).events_named(&"Swapped")).is_empty()


func test_the_conditions_run_in_order() -> void:
	var game := _game()
	FixtureItemModes.swap(game, P1)
	_take(game, P1, &"package")
	FixtureItemModes.swap(game, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_swap", &"two_handed"])


func test_a_downed_player_cannot_swap() -> void:
	var game := _game()
	var tool := _take(game, P2, &"tool")
	game.state.player(P2).life = PlayerState.Life.DOWNED
	FixtureItemModes.swap(game, P2, 5)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	assert_int(game.state.player(P2).held_item).is_equal(tool.id)
	assert_int(game.state.player(P2).belt_item).is_equal(-1)
	assert_array(game.view_of(P1).events_named(&"Swapped")).is_empty()


func test_a_dead_player_cannot_swap() -> void:
	var game := _game()
	var tool := _take(game, P2, &"tool")
	FixtureItemModes.swap(game, P2)
	game.state.player(P2).life = PlayerState.Life.DEAD
	FixtureItemModes.swap(game, P2, 6)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	assert_int(game.state.player(P2).belt_item).is_equal(tool.id)
	assert_array(game.view_of(P1).events_named(&"Swapped")).has_size(1)


func test_only_the_hand_item_is_used() -> void:
	var game := _game()
	_take(game, P1, &"tool")
	FixtureItemModes.swap(game, P1)
	FixtureModes.send(game, Intents.USE, P1, {"facing": NORTH}, 7)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do"])
	assert_array(FixtureModes.notes(game)).is_empty()
	FixtureItemModes.swap(game, P1)
	FixtureModes.send(game, Intents.USE, P1, {"facing": NORTH}, 8)
	assert_array(FixtureModes.notes(game)).is_equal(["tool used"])


func test_put_down_puts_down_only_the_hand_item() -> void:
	var game := _game()
	var tool := _take(game, P1, &"tool")
	FixtureItemModes.swap(game, P1)
	FixtureItemModes.put_down(game, P1, NORTH, 9)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"empty_hand"])
	assert_int(tool.where).is_equal(ItemState.Where.BELT)


func test_the_belt_item_shows_in_the_snapshots() -> void:
	var game := _game()
	var tool := _take(game, P1, &"tool")
	var package := _take(game, P1, &"package")
	FixtureModes.run_ticks(game, 1)
	var at := game.ticked_through()
	var other: Dictionary = game.view_of(P2).snapshots[at]
	assert_int(other["avatars"][P1]["held_item"]).is_equal(package.id)
	assert_int(other["avatars"][P1]["belt_item"]).is_equal(tool.id)
	assert_int(other["items"][tool.id]["where"]).is_equal(ItemState.Where.BELT)
	assert_int(other["items"][tool.id]["holder"]).is_equal(P1)


func test_a_swap_stops_the_raisers_raise() -> void:
	# Any applied action of a raiser stops its raise (RuleRunner, M4-4): RaiseStopped, then Swapped.
	var game := _raising()
	var tool := FixtureItemModes.lay(game, &"tool", RAISER)
	FixtureItemModes.pick_up(game, P3, tool)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	FixtureCombatModes.raise(game, P3, P2)
	assert_object(Channels.of_actor(game.state, P3)).is_not_null()
	var seen := game.view_of(P1).events.size()
	FixtureItemModes.swap(game, P3)
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"RaiseStopped", &"Swapped"]
	)
	assert_int(game.state.player(P3).belt_item).is_equal(tool.id)
	assert_int(game.state.player(P2).life_deadline).is_greater(game.ticked_through())
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_refused_swap_does_not_stop_the_raise() -> void:
	var game := _raising()
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureItemModes.swap(game, P3)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"nothing_to_swap"])
	assert_object(Channels.of_actor(game.state, P3)).is_not_null()
	assert_array(game.view_of(P1).events_named(&"RaiseStopped")).is_empty()


func test_a_swap_that_would_belt_a_two_handed_item_is_a_rule_error() -> void:
	# A mode whose Swap forgot HandNotTwoHanded must not put a package on the belt.
	var mode := FixtureItemModes.swapping(FixtureItemModes.basic())
	mode.actions[2].conditions = []
	var game := FixtureItemModes.in_round(mode, [P1, P2])
	var package := _take(game, P1, &"package")
	FixtureItemModes.swap(game, P1)
	assert_int(package.where).is_equal(ItemState.Where.HAND)
	assert_int(game.state.player(P1).belt_item).is_equal(-1)
	assert_array(game.view_of(P2).events_named(&"Swapped")).is_empty()
	assert_str(game.diagnostics[0]).contains("holds two-handed item")
	# The sender's seq is answered, as take answers its own rule error.
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"two_handed"])


func test_the_swap_rule_passes_the_mode_check() -> void:
	var check := ModeCheck.run(FixtureItemModes.swapping(FixtureItemModes.basic()))
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


func _game() -> Match:
	var game := FixtureItemModes.in_round(
		FixtureItemModes.swapping(FixtureItemModes.basic()), [P1, P2]
	)
	FixtureItemModes.stand(game, P1, HERE)
	FixtureItemModes.stand(game, P2, HERE)
	return game


## A round of the fixture raise mode with the swap: P1 armed, P2 where it will lie, P3 by it.
func _raising() -> Match:
	var mode := FixtureItemModes.swapping(FixtureCombatModes.raising())
	var game := FixtureCombatModes.in_round(mode, [P1, P2, P3])
	FixtureCombatModes.arm(game, P1, HERE)
	FixtureItemModes.stand(game, P2, LIES)
	FixtureItemModes.stand(game, P3, RAISER)
	return game


## An item of `kind_id` laid at `peer`'s feet and picked up by it.
func _take(game: Match, peer: int, kind_id: StringName) -> ItemState:
	var item := FixtureItemModes.lay(game, kind_id, game.state.player(peer).position)
	FixtureItemModes.pick_up(game, peer, item)
	assert_int(game.state.player(peer).held_item).is_equal(item.id)
	return item
