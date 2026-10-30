extends GdUnitTestSuite
## The tap and Drink (#1390; ARCHITECTURE §9.4.2): an Interact at the lobby's tap gives a mug (the
## hand, then the belt, then the feet; the cap vanishes the longest-lying loose mug, never a refusal
## while one lies loose); a Use on a full mug turns it empty (ItemChanged to everyone) and raises
## the drinker's drunk value, which every other peer sees on the avatar and the drinker in its
## SelfStatus; a Use on an empty mug is refused `nothing_to_do`; the fact `drunk_too_much` comes on
## each upward crossing of the threshold, never below it. Driven by FixtureBar.

const P1 := FixtureBar.P1
const P2 := FixtureBar.P2
const P3 := FixtureBar.P3


func test_a_pour_at_the_tap_fills_the_free_hand() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	FixtureBar.pour(game, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	var held := Items.held_by(game.state, P1)
	assert_object(held).is_not_null()
	assert_str(String(held.kind.id)).is_equal("mug")
	for peer: int in [P1, P2]:
		assert_array(game.view_of(peer).events_named(&"ItemSpawned")).has_size(1)
		assert_array(game.view_of(peer).events_named(&"ItemPickedUp")).has_size(1)


func test_a_pour_far_from_the_tap_is_out_of_reach() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	FixtureItemModes.stand(game, P1, FixtureBar.TAP + Vector3(5, 0, 0))
	FixtureBar.pour(game, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_reach"])
	assert_object(Items.held_by(game.state, P1)).is_null()


func test_full_hands_and_belt_put_the_old_hand_item_at_the_feet() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	var tools: Array[ItemState] = []
	for i in 3:
		tools.append(FixtureLobbyHands.give(game, P1, &"tool"))
	assert_int(game.state.player(P1).carried_items().size()).is_equal(3)
	var in_hand := Items.held_by(game.state, P1)
	var placed_before := game.view_of(P2).events_named(&"ItemPlaced").size()
	FixtureBar.pour(game, P1, 9)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_str(String(Items.held_by(game.state, P1).kind.id)).is_equal("mug")
	assert_int(in_hand.where).is_equal(ItemState.Where.GROUND)
	assert_int(game.view_of(P2).events_named(&"ItemPlaced").size()).is_equal(placed_before + 1)
	assert_int(tools.size()).is_equal(3)


func test_a_full_hand_and_a_free_belt_belt_the_old_hand_item() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	var tool := FixtureLobbyHands.give(game, P1, &"tool")
	FixtureBar.pour(game, P1, 9)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(tool.where).is_equal(ItemState.Where.BELT)
	assert_str(String(Items.held_by(game.state, P1).kind.id)).is_equal("mug")


func test_the_cap_vanishes_the_longest_lying_mug_and_never_refuses_spam() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	var first: ItemState = null
	for seq in FixtureBar.MUGS + 2:
		FixtureBar.pour(game, P1, 10 * seq + 1)
		if first == null:
			first = Items.held_by(game.state, P1)
		FixtureItemModes.put_down(game, P1, Vector3.FORWARD, 10 * seq + 2)
		FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(_count(game, &"mug")).is_equal(FixtureBar.MUGS)
	var vanished := game.view_of(P2).events_named(&"ItemVanished")
	assert_array(vanished).has_size(2)
	assert_int((vanished[0] as ItemVanishedEvent).item).is_equal(first.id)


## The flood guard (the base mode's tap has it): one peer pouring on every tick gets one pour per
## Cooldown step and `too_soon` for the rest, so the events a pour emits to everyone stay bounded.
func test_a_burst_of_pours_gets_one_per_cooldown_and_too_soon_for_the_rest() -> void:
	var game := FixtureBar.at_bar(FixtureBar.guarded(), [P1, P2])
	var step := Ticks.from_seconds(FixtureBar.POUR_S)
	assert_int(step).is_greater(1)
	var sends := 2 * step + 1
	for seq in sends:
		FixtureBar.pour(game, P1, seq + 1)
		FixtureModes.run_ticks(game, 1)
	var refused := FixtureModes.rejections(game, P1)
	assert_array(refused).has_size(sends - 3)
	for reason: StringName in refused:
		assert_str(String(reason)).is_equal("too_soon")
	assert_int(game.state.player(P1).carried_items().size()).is_equal(3)
	assert_array(game.view_of(P2).events_named(&"ItemSpawned")).has_size(3)
	assert_array(FixtureModes.rejections(game, P2)).is_empty()


func test_the_pour_cooldown_is_per_player() -> void:
	var game := FixtureBar.at_bar(FixtureBar.guarded(), [P1, P2])
	FixtureBar.pour(game, P1, 1)
	FixtureBar.pour(game, P2, 1)
	FixtureBar.pour(game, P1, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"too_soon"])
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	assert_object(Items.held_by(game.state, P2)).is_not_null()


func test_with_every_mug_held_a_pour_is_unavailable() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	for seq in FixtureBar.MUGS:
		FixtureBar.pour(game, P1, seq + 1)
	FixtureBar.pour(game, P2, 9)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unavailable"])


func test_a_drink_empties_the_mug_and_everyone_sees_the_drunk_value() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2, P3])
	FixtureBar.pour(game, P1, 1)
	var mug := Items.held_by(game.state, P1)
	FixtureBar.drink(game, P1, 2)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_str(String(mug.kind.id)).is_equal("mug_empty")
	assert_int(game.state.player(P1).held_item).is_equal(mug.id)
	assert_int(game.state.player(P1).drunk).is_equal(FixtureBar.AMOUNT)
	for peer: int in [P1, P2, P3]:
		var changed := game.view_of(peer).events_named(&"ItemChanged")
		assert_array(changed).has_size(1)
		assert_str(String((changed[0] as ItemChangedEvent).kind)).is_equal("mug_empty")
	var at := game.ticked_through()
	for peer: int in [P2, P3]:
		var avatars: Dictionary = game.view_of(peer).snapshots[at]["avatars"]
		assert_int(avatars[P1]["drunk"] as int).is_equal(FixtureBar.AMOUNT)
	assert_bool((game.view_of(P1).snapshots[at]["avatars"] as Dictionary).has(P1)).is_false()
	var own := game.view_of(P1).events_named(&"SelfStatus")
	assert_int((own[own.size() - 1] as SelfStatusEvent).drunk).is_equal(FixtureBar.AMOUNT)
	assert_array(game.view_of(P2).events_named(&"SelfStatus").filter(_status_of(P1))).is_empty()


func test_a_use_on_an_empty_mug_does_nothing() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	FixtureBar.pour(game, P1, 1)
	FixtureBar.drink(game, P1, 2)
	FixtureBar.drink(game, P1, 3)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do"])
	assert_int(game.state.player(P1).drunk).is_equal(FixtureBar.AMOUNT)


func test_drinks_stack_up_to_the_max_and_too_much_comes_once_on_the_crossing() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	_drink_one(game, P1, 1)
	_drink_one(game, P1, 3)
	assert_int(game.state.player(P1).drunk).is_equal(2 * FixtureBar.AMOUNT)
	assert_array(FixtureModes.notes(game).filter(_is_too_much)).is_empty()
	_drink_one(game, P1, 5)
	assert_int(game.state.player(P1).drunk).is_equal(FixtureBar.MAX)
	# The fact names the drinker (Fact.player), which the limp (#1393) reads.
	assert_array(FixtureModes.notes(game).filter(_is_too_much)).is_equal(["too much %d" % P1])
	_drink_one(game, P1, 7)
	assert_int(game.state.player(P1).drunk).is_equal(FixtureBar.MAX)
	assert_array(FixtureModes.notes(game).filter(_is_too_much)).has_size(1)


func test_too_much_comes_again_after_sobering_below_the_threshold() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	game.state.player(P1).drunk = FixtureBar.TOO_MUCH - 1
	game.state.player(P1).drunk_stamp = game.ticked_through() + 1000
	_drink_one(game, P1, 1)
	assert_array(FixtureModes.notes(game).filter(_is_too_much)).has_size(1)
	game.state.player(P1).drunk = FixtureBar.TOO_MUCH - FixtureBar.AMOUNT
	_drink_one(game, P1, 3)
	assert_int(game.state.player(P1).drunk).is_equal(FixtureBar.TOO_MUCH)
	assert_array(FixtureModes.notes(game).filter(_is_too_much)).has_size(2)


func test_the_empties_cap_vanishes_the_longest_lying_empty() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	for seq in FixtureBar.EMPTIES + 1:
		_drink_one(game, P1, 10 * seq + 1)
		FixtureItemModes.put_down(game, P1, Vector3.FORWARD, 10 * seq + 3)
		FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(_count(game, &"mug_empty")).is_equal(FixtureBar.EMPTIES)
	assert_array(game.view_of(P2).events_named(&"ItemVanished")).has_size(1)


func test_a_mug_put_down_vanishes_after_its_time() -> void:
	var game := FixtureBar.at_bar(FixtureBar.mode(), [P1, P2])
	FixtureBar.pour(game, P1, 1)
	FixtureItemModes.put_down(game, P1, Vector3.FORWARD, 2)
	var mug: ItemState = game.state.items.values()[0]
	assert_int(mug.where).is_equal(ItemState.Where.GROUND)
	FixtureModes.run_ticks(game, Ticks.from_seconds(FixtureBar.MUG_S) - 1)
	assert_bool(game.state.items.has(mug.id)).is_true()
	FixtureModes.run_ticks(game, 2)
	assert_bool(game.state.items.has(mug.id)).is_false()


## `peer` pours (seq) and drinks (seq + 1).
func _drink_one(game: Match, peer: int, seq: int) -> void:
	FixtureBar.pour(game, peer, seq)
	FixtureBar.drink(game, peer, seq + 1)


func _count(game: Match, kind_id: StringName) -> int:
	var found := 0
	for id: int in game.state.items:
		if game.state.items[id].kind.id == kind_id:
			found += 1
	return found


func _is_too_much(note: String) -> bool:
	return note.begins_with("too much")


func _status_of(peer: int) -> Callable:
	return func(event: MatchEvent) -> bool: return (event as SelfStatusEvent).peer == peer
