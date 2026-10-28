extends GdUnitTestSuite
## Draw and the three places (ARCHITECTURE §7.1, §9.4; GDD §6 "Drawing from the belt", #1040
## c6320249563, #1218): PlaceInRange (`no_such_place`) and PlaceChanges (`same_place`), then
## DrawPlace, which brings the place into the hand (Items.select) and emits Swapped with the place
## to everyone; a two-handed hand item is put down at the feet first, no refusal. X (Swap) goes
## back to the place held last. A take fills the selected place when it is empty, else the lowest
## free place, which becomes selected. Driven by commands through the fixture item mode with the
## swap and the draw (a two-handed `package`, a one-handed `tool`) and the fixture raise mode;
## asserted on the events, view_of and the match state.

const P1 := 1
const P2 := 2
const P3 := 3
const HERE := Vector3(0, 0, 0)
const NORTH := Vector3(0, 0, 1)
const LIES := Vector3(0, 0, 1)
const RAISER := Vector3(1.5, 0, 1)


func test_a_draw_brings_the_place_into_the_hand_and_everyone_sees_it() -> void:
	var game := _game()
	var first := _take(game, P1, &"tool")
	var second := _take(game, P1, &"tool")
	var player := game.state.player(P1)
	assert_array(Array(player.places)).is_equal([first.id, second.id, -1])
	assert_int(player.selected_place).is_equal(1)
	var seen := game.view_of(P2).events.size()
	FixtureItemModes.draw(game, P1, 0, 3)
	assert_int(player.selected_place).is_equal(0)
	assert_int(player.last_place).is_equal(1)
	assert_int(player.held_item).is_equal(first.id)
	assert_int(player.belt_item).is_equal(second.id)
	assert_int(first.where).is_equal(ItemState.Where.HAND)
	assert_int(second.where).is_equal(ItemState.Where.BELT)
	for peer: int in [P1, P2]:
		var swapped := game.view_of(peer).events_named(&"Swapped")
		assert_dict(swapped[-1].to_dict()).is_equal({"peer": P1, "place": 0})
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal([&"Swapped"])
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_an_item_keeps_its_place_and_an_empty_place_is_an_empty_hand() -> void:
	var game := _game()
	var tool := _take(game, P1, &"tool")
	var player := game.state.player(P1)
	FixtureItemModes.draw(game, P1, 2)
	assert_int(player.held_item).is_equal(-1)
	assert_array(Array(player.places)).is_equal([tool.id, -1, -1])
	assert_int(player.belt_item).is_equal(tool.id)
	assert_int(player.belt_item2).is_equal(-1)
	FixtureItemModes.draw(game, P1, 1)
	assert_int(player.held_item).is_equal(-1)
	FixtureItemModes.draw(game, P1, 0)
	assert_int(player.held_item).is_equal(tool.id)
	assert_array(Array(player.places)).is_equal([tool.id, -1, -1])
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_x_goes_back_to_the_place_held_last() -> void:
	var game := _game()
	var first := _take(game, P1, &"tool")
	var second := _take(game, P1, &"tool")
	var third := _take(game, P1, &"tool")
	var player := game.state.player(P1)
	assert_array(Array(player.places)).is_equal([first.id, second.id, third.id])
	FixtureItemModes.draw(game, P1, 0)
	FixtureItemModes.swap(game, P1)
	assert_int(player.held_item).is_equal(third.id)
	FixtureItemModes.swap(game, P1)
	assert_int(player.held_item).is_equal(first.id)
	var swapped := game.view_of(P2).events_named(&"Swapped")
	assert_dict(swapped[-1].to_dict()).is_equal({"peer": P1, "place": 0})
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_a_draw_with_a_two_handed_item_puts_it_down_at_the_feet() -> void:
	var game := _game()
	var tool := _take(game, P1, &"tool")
	var package := _take(game, P1, &"package")
	var player := game.state.player(P1)
	assert_int(player.selected_place).is_equal(1)
	var seen := game.view_of(P2).events.size()
	FixtureItemModes.draw(game, P1, 0)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	# The fixture's item_rested reactions note the put-down in between.
	var names := FixtureItemModes.names_after(game, P2, seen).filter(
		func(name: StringName) -> bool: return name != &"FixtureNote"
	)
	assert_array(names).is_equal([&"ItemPlaced", &"Swapped"])
	var placed := game.view_of(P2).events_named(&"ItemPlaced")[-1] as ItemPlacedEvent
	assert_int(placed.item).is_equal(package.id)
	assert_str(String(placed.cause)).is_equal("put_down")
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_int(player.held_item).is_equal(tool.id)
	assert_array(Array(player.places)).is_equal([tool.id, -1, -1])
	assert_array(Array(game.diagnostics)).is_empty()


func test_x_with_a_two_handed_item_stays_refused() -> void:
	var game := _game()
	_take(game, P1, &"tool")
	var package := _take(game, P1, &"package")
	FixtureItemModes.swap(game, P1, 4)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"two_handed"])
	assert_int(game.state.player(P1).held_item).is_equal(package.id)


func test_a_place_out_of_range_is_refused() -> void:
	var game := _game()
	_take(game, P1, &"tool")
	for place: int in [-1, 3, 255]:
		FixtureItemModes.draw(game, P1, place)
	assert_array(FixtureModes.rejections(game, P1)).is_equal(
		[&"no_such_place", &"no_such_place", &"no_such_place"]
	)
	assert_int(game.state.player(P1).selected_place).is_equal(0)
	assert_array(game.view_of(P2).events_named(&"Swapped")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_selected_place_is_refused_and_only_its_sender_hears() -> void:
	var game := _game()
	_take(game, P1, &"tool")
	var seen := game.view_of(P2).events.size()
	FixtureItemModes.draw(game, P1, 0, 9)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"same_place"])
	var rejected := game.view_of(P1).events_named(&"Rejected")[0] as RejectedEvent
	assert_int(rejected.seq).is_equal(9)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_empty()


func test_a_draw_place_that_is_not_a_number_is_no_such_place() -> void:
	var game := _game()
	FixtureModes.send(game, Intents.DRAW, P1, {"place": "two"})
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"no_such_place"])


func test_a_downed_player_cannot_draw() -> void:
	var game := _game()
	_take(game, P2, &"tool")
	game.state.player(P2).life = PlayerState.Life.DOWNED
	FixtureItemModes.draw(game, P2, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	assert_int(game.state.player(P2).selected_place).is_equal(0)


func test_a_take_fills_the_selected_place_when_it_is_empty() -> void:
	# GDD §6: "into the place in the hand when it is empty", even with a lower place free.
	var game := _game()
	FixtureItemModes.draw(game, P1, 2)
	var tool := _take(game, P1, &"tool")
	var player := game.state.player(P1)
	assert_array(Array(player.places)).is_equal([-1, -1, tool.id])
	assert_int(player.selected_place).is_equal(2)
	var picked := game.view_of(P2).events_named(&"ItemPickedUp")[-1] as ItemPickedUpEvent
	assert_dict(picked.to_dict()).is_equal({"peer": P1, "item": tool.id, "belted": -1, "place": 2})


func test_a_take_with_a_full_hand_goes_to_the_lowest_free_place_and_selects_it() -> void:
	var game := _game()
	FixtureItemModes.draw(game, P1, 1)
	var first := _take(game, P1, &"tool")
	var second := _take(game, P1, &"tool")
	var player := game.state.player(P1)
	assert_array(Array(player.places)).is_equal([second.id, first.id, -1])
	assert_int(player.selected_place).is_equal(0)
	assert_int(player.last_place).is_equal(1)
	assert_int(first.where).is_equal(ItemState.Where.BELT)
	var picked := game.view_of(P2).events_named(&"ItemPickedUp")[-1] as ItemPickedUpEvent
	assert_dict(picked.to_dict()).is_equal(
		{"peer": P1, "item": second.id, "belted": first.id, "place": 0}
	)


func test_with_all_three_full_the_hand_item_rests_where_the_taken_one_lay() -> void:
	var game := _game()
	var first := _take(game, P1, &"tool")
	var second := _take(game, P1, &"tool")
	var third := _take(game, P1, &"tool")
	var spot := Vector3(0.5, 0, 0)
	var fourth := FixtureItemModes.lay(game, &"tool", spot)
	FixtureItemModes.pick_up(game, P1, fourth)
	var player := game.state.player(P1)
	assert_array(Array(player.places)).is_equal([first.id, second.id, fourth.id])
	assert_int(third.where).is_equal(ItemState.Where.GROUND)
	assert_vector(third.position).is_equal(spot)
	var placed := game.view_of(P2).events_named(&"ItemPlaced")[-1] as ItemPlacedEvent
	assert_str(String(placed.cause)).is_equal("swap")


func test_a_two_handed_item_is_only_ever_in_the_hand() -> void:
	# A two-handed hand item and a one-handed take: the take goes onto the lowest free belt place;
	# with both full the lower one's item is put down at the feet first.
	var game := _game()
	FixtureItemModes.draw(game, P1, 1)
	var package := _take(game, P1, &"package")
	var first := _take_beside(game, P1)
	var second := _take_beside(game, P1)
	var player := game.state.player(P1)
	assert_array(Array(player.places)).is_equal([first.id, package.id, second.id])
	var third := _take_beside(game, P1)
	assert_array(Array(player.places)).is_equal([third.id, package.id, second.id])
	assert_int(first.where).is_equal(ItemState.Where.GROUND)
	assert_int(player.held_item).is_equal(package.id)
	var picked := game.view_of(P2).events_named(&"ItemPickedUp")[-1] as ItemPickedUpEvent
	assert_dict(picked.to_dict()).is_equal(
		{"peer": P1, "item": third.id, "belted": third.id, "place": 0}
	)


func test_a_leave_drops_all_three_hand_first_then_the_belt_in_place_order() -> void:
	var game := _game()
	var first := _take(game, P1, &"tool")
	var second := _take(game, P1, &"tool")
	var third := _take(game, P1, &"tool")
	FixtureItemModes.draw(game, P1, 1)
	var seen := game.view_of(P2).events.size()
	FixtureModes.send(game, Intents.PEER_LEFT, P1)
	var dropped: Array[int] = []
	for event: MatchEvent in game.view_of(P2).events.slice(seen):
		if event is ItemPlacedEvent:
			dropped.append((event as ItemPlacedEvent).item)
	assert_array(dropped).is_equal([second.id, first.id, third.id])
	assert_array(Array(game.state.player(P1).places)).is_equal([-1, -1, -1])


func test_a_draw_stops_the_raisers_raise() -> void:
	var game := _raising()
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureCombatModes.raise(game, P3, P2)
	var seen := game.view_of(P1).events.size()
	FixtureItemModes.draw(game, P3, 1)
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"RaiseStopped", &"Swapped"]
	)


func test_a_reset_clears_every_place() -> void:
	var game := _game()
	_take(game, P1, &"tool")
	_take(game, P1, &"tool")
	_take(game, P1, &"tool")
	FixtureItemModes.draw(game, P1, 1)
	var player := game.state.player(P1)
	MatchState.reset_player(player, game.state.player_rules)
	assert_array(Array(player.places)).is_equal([-1, -1, -1])
	assert_int(player.selected_place).is_equal(0)
	assert_int(player.last_place).is_equal(PlayerState.FIRST_LAST_PLACE)


func test_the_draw_rule_passes_the_mode_check() -> void:
	var check := ModeCheck.run(_mode())
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


func _mode() -> GameMode:
	return FixtureItemModes.drawing(FixtureItemModes.swapping(FixtureItemModes.basic()))


func _game() -> Match:
	var game := FixtureItemModes.in_round(_mode(), [P1, P2])
	FixtureItemModes.stand(game, P1, HERE)
	FixtureItemModes.stand(game, P2, HERE)
	return game


## A round of the fixture raise mode with the draw: P1 armed, P2 where it will lie, P3 by it.
func _raising() -> Match:
	var mode := FixtureItemModes.drawing(FixtureCombatModes.raising())
	var game := FixtureCombatModes.in_round(mode, [P1, P2, P3])
	FixtureCombatModes.arm(game, P1, HERE)
	FixtureItemModes.stand(game, P2, LIES)
	FixtureItemModes.stand(game, P3, RAISER)
	return game


## An item of `kind_id` laid at `peer`'s feet and picked up by it, into the hand.
func _take(game: Match, peer: int, kind_id: StringName) -> ItemState:
	var item := FixtureItemModes.lay(game, kind_id, game.state.player(peer).position)
	FixtureItemModes.pick_up(game, peer, item)
	assert_int(game.state.player(peer).held_item).is_equal(item.id)
	return item


## A tool laid at `peer`'s feet and picked up beside its two-handed hand item: onto the belt.
func _take_beside(game: Match, peer: int) -> ItemState:
	var item := FixtureItemModes.lay(game, &"tool", game.state.player(peer).position)
	FixtureItemModes.pick_up(game, peer, item)
	assert_int(item.where).is_equal(ItemState.Where.BELT)
	return item
