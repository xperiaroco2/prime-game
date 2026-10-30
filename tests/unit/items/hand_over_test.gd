extends GdUnitTestSuite
## The hand-over (#1389; ARCHITECTURE §7.1, §9.4; GDD §6 "The hand and the belt"), driven by
## HandOver commands through a seeded Match: the item leaves the giver's hand and arrives as a give
## does, ItemPickedUp (its `peer` the receiver) to everyone; every refusal goes to the sender alone
## with its reason, and nothing moves.

const P1 := 1
const P2 := 2
const P3 := 3
const NOBODY := 999
const NEAR := Vector3(0, 0, 1.5)
const FAR := Vector3(0, 0, 30)


func test_the_hand_item_goes_into_an_empty_hand_and_everyone_sees_it() -> void:
	var game := _game()
	var gift := FixtureHandOverModes.hold(game, P1, &"gift")
	var seen := _counts(game)
	var moves := gift.moves
	FixtureHandOverModes.hand_over(game, P1, P2)
	for peer: int in [P1, P2, P3]:
		var names := FixtureItemModes.names_after(game, peer, seen[peer])
		assert_array(names).override_failure_message(str(peer)).is_equal([&"ItemPickedUp"])
		var picked := _last_picked(game, peer)
		assert_int(picked.peer).is_equal(P2)
		assert_int(picked.item).is_equal(gift.id)
		assert_int(picked.belted).is_equal(-1)
		assert_int(picked.place).is_equal(game.state.player(P2).selected_place)
	var giver := game.state.player(P1)
	assert_int(giver.held_item).is_equal(-1)
	assert_array(Array(giver.places)).is_equal([-1, -1, -1])
	assert_int(gift.holder).is_equal(P2)
	assert_int(gift.where).is_equal(ItemState.Where.HAND)
	assert_int(gift.moves).is_equal(moves + 1)
	assert_int(game.state.player(P2).held_item).is_equal(gift.id)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_receivers_one_handed_hand_item_moves_to_its_belt() -> void:
	var game := _game()
	var tool := FixtureHandOverModes.hold(game, P2, &"tool")
	var gift := FixtureHandOverModes.hold(game, P1, &"gift")
	FixtureHandOverModes.hand_over(game, P1, P2)
	var picked := _last_picked(game, P3)
	assert_int(picked.belted).is_equal(tool.id)
	var receiver := game.state.player(P2)
	assert_int(receiver.held_item).is_equal(gift.id)
	assert_int(tool.where).is_equal(ItemState.Where.BELT)
	assert_int(receiver.place_of(tool.id)).is_not_equal(receiver.selected_place)


func test_a_full_receiver_puts_its_hand_item_down_at_its_feet_first() -> void:
	var game := _game()
	var held: Array[ItemState] = []
	for i in 3:
		held.append(FixtureHandOverModes.hold(game, P2, &"tool"))
	var hand: ItemState = game.state.items[game.state.player(P2).held_item]
	var gift := FixtureHandOverModes.hold(game, P1, &"gift")
	var seen := _counts(game)
	FixtureHandOverModes.hand_over(game, P1, P2)
	var names := FixtureItemModes.names_after(game, P3, seen[P3])
	names = names.filter(func(name: StringName) -> bool: return name != &"FixtureNote")
	assert_array(names).is_equal([&"ItemPlaced", &"ItemPickedUp"])
	var placed: ItemPlacedEvent = game.view_of(P3).events_named(&"ItemPlaced").back()
	assert_int(placed.item).is_equal(hand.id)
	assert_str(String(placed.cause)).is_equal(String(Items.PUT_DOWN))
	assert_int(hand.where).is_equal(ItemState.Where.GROUND)
	assert_int(game.state.player(P2).held_item).is_equal(gift.id)
	var rested := FixtureModes.notes(game).filter(
		func(note: String) -> bool: return note.begins_with("rested %d put_down" % hand.id)
	)
	assert_int(rested.size()).is_equal(1)


func test_beside_a_two_handed_hand_item_the_gift_goes_onto_the_belt() -> void:
	var game := _game()
	var package := FixtureHandOverModes.hold(game, P2, &"package")
	var gift := FixtureHandOverModes.hold(game, P1, &"gift")
	FixtureHandOverModes.hand_over(game, P1, P2)
	var picked := _last_picked(game, P1)
	assert_int(picked.belted).is_equal(gift.id)
	assert_int(gift.where).is_equal(ItemState.Where.BELT)
	assert_int(game.state.player(P2).held_item).is_equal(package.id)


func test_an_empty_hand_is_refused_even_with_a_belt_item() -> void:
	var game := _game()
	_refused(game, P2, HoldsItem.EMPTY_HAND)
	FixtureHandOverModes.hold(game, P1, &"gift")
	FixtureItemModes.swap(game, P1)
	assert_int(game.state.player(P1).held_item).is_equal(-1)
	_refused(game, P2, HoldsItem.EMPTY_HAND)


func test_a_two_handed_or_unmarked_item_is_refused() -> void:
	var game := _game()
	FixtureHandOverModes.hold(game, P1, &"package")
	_refused(game, P2, HandNotTwoHanded.TWO_HANDED)
	var other := _game()
	FixtureHandOverModes.hold(other, P1, &"tool")
	_refused(other, P2, HandHandable.NOT_HANDABLE)


func test_the_receiver_must_be_another_living_present_player() -> void:
	var game := _game()
	FixtureHandOverModes.hold(game, P1, &"gift")
	_refused(game, P1, RejectReasons.BAD_ARGS)
	_refused(game, 0, TargetLiving.NOT_LIVING)
	_refused(game, NOBODY, TargetLiving.NOT_LIVING)
	for life: PlayerState.Life in [
		PlayerState.Life.DOWNED, PlayerState.Life.DEAD, PlayerState.Life.LEFT
	]:
		game.state.player(P2).life = life
		_refused(game, P2, TargetLiving.NOT_LIVING)
	game.state.player(P2).life = PlayerState.Life.ALIVE
	FixtureHandOverModes.hand_over(game, P1, P2)
	assert_int(game.state.player(P2).held_item).is_not_equal(-1)


func test_the_receiver_must_be_in_reach_and_in_sight() -> void:
	var game := _game()
	FixtureHandOverModes.hold(game, P1, &"gift")
	FixtureItemModes.stand(game, P2, Vector3(0, 0, FixtureHandOverModes.REACH_M + 0.1))
	_refused(game, P2, TargetInReach.OUT_OF_REACH)
	var walled := FlatWorldQuery.new().add_wall(AABB(Vector3(-2, 0, 0.7), Vector3(4, 3, 0.1)))
	var behind := _game(walled)
	FixtureHandOverModes.hold(behind, P1, &"gift")
	_refused(behind, P2, TargetInSight.BLOCKED)


func test_a_waist_high_counter_does_not_block_it_when_the_sight_aims_at_the_eye() -> void:
	var counter := AABB(Vector3(-2, 0, 0.7), Vector3(4, 1, 0.1))
	var game := _game(FlatWorldQuery.new().add_wall(counter))
	var gift := FixtureHandOverModes.hold(game, P1, &"gift")
	FixtureHandOverModes.hand_over(game, P1, P2)
	assert_int(gift.holder).is_equal(P2)
	# The raise's sight (at the feet) is blocked by the same counter.
	var low := FixtureHandOverModes.basic()
	(low.actions.back() as Rule).conditions[5].set(&"at_eye", false)
	var feet := _game(FlatWorldQuery.new().add_wall(counter), low)
	FixtureHandOverModes.hold(feet, P1, &"gift")
	_refused(feet, P2, TargetInSight.BLOCKED)


func test_a_phase_without_the_accept_row_and_a_dead_sender_are_not_accepted() -> void:
	var mode := FixtureHandOverModes.basic()
	var round_spec := mode.find_phase(&"round")
	for accept: AcceptSpec in round_spec.accepts.duplicate():
		if accept.intent == Intents.HAND_OVER:
			round_spec.accepts.erase(accept)
	var game := _game(null, mode)
	FixtureHandOverModes.hold(game, P1, &"gift")
	_refused(game, P2, RejectReasons.NOT_ACCEPTED)
	var dead := _game()
	FixtureHandOverModes.hold(dead, P1, &"gift")
	dead.state.player(P1).life = PlayerState.Life.DEAD
	_refused(dead, P2, RejectReasons.NOT_ACCEPTED)


func test_the_hand_over_is_deterministic_for_a_seed() -> void:
	var logs: Array[String] = []
	for i in 2:
		var game := _game()
		FixtureHandOverModes.hold(game, P2, &"tool")
		FixtureHandOverModes.hold(game, P1, &"gift")
		FixtureHandOverModes.hand_over(game, P1, P2)
		logs.append(str(game.view_of(P3).event_names()) + FixtureHandOverModes.signature(game))
	assert_str(logs[0]).is_equal(logs[1])


## The hand-over mode in the round with P1 at the origin, P2 1.5 m away and P3 far off.
func _game(world: WorldQuery = null, mode: GameMode = null) -> Match:
	var used := mode if mode != null else FixtureHandOverModes.basic()
	var game := FixtureItemModes.in_round(used, [P1, P2, P3], world)
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, NEAR)
	FixtureItemModes.stand(game, P3, FAR)
	return game


## A HandOver from P1 to `target` is refused with `reason` to P1 alone, and nothing moves.
func _refused(game: Match, target: int, reason: StringName) -> void:
	var before := FixtureHandOverModes.signature(game)
	var seen := _counts(game)
	FixtureHandOverModes.hand_over(game, P1, target)
	var label := "%d %s" % [target, reason]
	(
		assert_array(FixtureItemModes.names_after(game, P1, seen[P1]))
		. override_failure_message(label)
		. is_equal([&"Rejected"])
	)
	assert_array(FixtureModes.rejections(game, P1).slice(-1)).is_equal([reason])
	for peer: int in [P2, P3]:
		assert_array(FixtureItemModes.names_after(game, peer, seen[peer])).is_empty()
	assert_str(FixtureHandOverModes.signature(game)).override_failure_message(label).is_equal(
		before
	)
	assert_array(Array(game.diagnostics)).is_empty()


func _counts(game: Match) -> Dictionary[int, int]:
	var counts: Dictionary[int, int] = {}
	for peer: int in [P1, P2, P3]:
		counts[peer] = game.view_of(peer).event_names().size()
	return counts


func _last_picked(game: Match, peer: int) -> ItemPickedUpEvent:
	return game.view_of(peer).events_named(&"ItemPickedUp").back() as ItemPickedUpEvent
