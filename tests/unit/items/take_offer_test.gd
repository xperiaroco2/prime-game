extends GdUnitTestSuite
## The take of a hand-over offer and the offer's ends (#1434; ARCHITECTURE §7.1, §9.4; GDD §6
## "Handing over"), driven by HandOver, TakeOffer, CancelOffer and the item intents through a
## seeded Match: the receiver's E moves the item exactly as a pick-up from the floor would; each
## end of an offer is one OfferEnded to everyone, after which a take is `no_offer`.

const P1 := 1
const P2 := 2
const P3 := 3
const NEAR := Vector3(0, 0, 1.5)
const FAR := Vector3(0, 0, 30)


func test_the_receiver_takes_the_offer_and_it_lands_as_a_pick_up() -> void:
	var game := _offered(&"gift")
	var gift: ItemState = game.state.items[game.state.player(P1).held_item]
	var moves := gift.moves
	var seen := _counts(game)
	FixtureHandOverModes.take_offer(game, P2, P1)
	for peer: int in [P1, P2, P3]:
		var names := FixtureItemModes.names_after(game, peer, seen[peer])
		assert_array(names).override_failure_message(str(peer)).is_equal(
			[&"ItemPickedUp", &"OfferEnded"]
		)
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
	assert_object(Offers.of_giver(game.state, P1)).is_null()
	assert_array(Array(game.diagnostics)).is_empty()


func test_without_the_take_the_item_stays_with_the_giver() -> void:
	var game := _offered(&"gift")
	var gift: ItemState = game.state.items[game.state.player(P1).held_item]
	FixtureModes.run_ticks(game, 10)
	assert_int(gift.holder).is_equal(P1)
	assert_int(gift.where).is_equal(ItemState.Where.HAND)
	assert_int(game.state.player(P2).held_item).is_equal(-1)


func test_the_receivers_one_handed_hand_item_moves_to_its_belt() -> void:
	var game := _game()
	var tool := FixtureHandOverModes.hold(game, P2, &"tool")
	var gift := _offer(game, &"gift")
	FixtureHandOverModes.take_offer(game, P2, P1)
	assert_int(_last_picked(game, P3).belted).is_equal(tool.id)
	var receiver := game.state.player(P2)
	assert_int(receiver.held_item).is_equal(gift.id)
	assert_int(tool.where).is_equal(ItemState.Where.BELT)


func test_a_full_receiver_puts_its_hand_item_down_at_its_feet_first() -> void:
	var game := _game()
	for i in 3:
		FixtureHandOverModes.hold(game, P2, &"tool")
	var hand: ItemState = game.state.items[game.state.player(P2).held_item]
	var gift := _offer(game, &"gift")
	var seen := _counts(game)
	FixtureHandOverModes.take_offer(game, P2, P1)
	var names := FixtureItemModes.names_after(game, P3, seen[P3])
	names = names.filter(func(name: StringName) -> bool: return name != &"FixtureNote")
	assert_array(names).is_equal([&"ItemPlaced", &"ItemPickedUp", &"OfferEnded"])
	var placed: ItemPlacedEvent = game.view_of(P3).events_named(&"ItemPlaced").back()
	assert_int(placed.item).is_equal(hand.id)
	assert_str(String(placed.cause)).is_equal(String(Items.PUT_DOWN))
	assert_int(hand.where).is_equal(ItemState.Where.GROUND)
	assert_int(game.state.player(P2).held_item).is_equal(gift.id)


func test_two_handed_items_follow_the_pick_ups_hand_rules() -> void:
	# A one-handed gift beside a two-handed hand item goes onto the belt.
	var belt := _game()
	var package := FixtureHandOverModes.hold(belt, P2, &"package")
	var gift := _offer(belt, &"gift")
	FixtureHandOverModes.take_offer(belt, P2, P1)
	assert_int(_last_picked(belt, P1).belted).is_equal(gift.id)
	assert_int(gift.where).is_equal(ItemState.Where.BELT)
	assert_int(belt.state.player(P2).held_item).is_equal(package.id)
	# A two-handed gift into a one-handed hand: the old item onto the belt.
	var onto := _game()
	var tool := FixtureHandOverModes.hold(onto, P2, &"tool")
	var crate := _offer(onto, &"package")
	FixtureHandOverModes.take_offer(onto, P2, P1)
	assert_int(onto.state.player(P2).held_item).is_equal(crate.id)
	assert_int(tool.where).is_equal(ItemState.Where.BELT)
	# Two-handed into two-handed swaps: the old one rests at the receiver's feet.
	var swap := _game()
	var old := FixtureHandOverModes.hold(swap, P2, &"package")
	var box := _offer(swap, &"package")
	FixtureHandOverModes.take_offer(swap, P2, P1)
	assert_int(swap.state.player(P2).held_item).is_equal(box.id)
	assert_int(old.where).is_equal(ItemState.Where.GROUND)
	var placed: ItemPlacedEvent = swap.view_of(P3).events_named(&"ItemPlaced").back()
	assert_str(String(placed.cause)).is_equal(String(Items.SWAP))
	assert_float(old.position.distance_to(NEAR)).is_less(0.5)
	assert_array(Array(swap.diagnostics)).is_empty()


func test_a_take_with_no_offer_or_an_offer_to_someone_else_is_no_offer() -> void:
	var game := _game()
	FixtureHandOverModes.hold(game, P1, &"gift")
	_take_refused(game, P2, P1, Offers.NO_OFFER)
	FixtureHandOverModes.hand_over(game, P1, P2)
	# P3 near P1 names P1's offer to P2.
	FixtureItemModes.stand(game, P3, Vector3(-1.5, 0, 0))
	_take_refused(game, P3, P1, Offers.NO_OFFER)
	_take_refused(game, P2, P2, RejectReasons.BAD_ARGS)
	assert_int(Offers.live(game.state, P1).target).is_equal(P2)


func test_a_limp_receiver_is_not_accepted_and_the_offer_ends() -> void:
	var game := _offered(&"gift")
	FixtureHandOverModes.make_limp(game, P2)
	_take_refused(game, P2, P1, RejectReasons.NOT_ACCEPTED)
	_ends_on_tick(game)


func test_the_take_needs_reach_and_sight() -> void:
	var game := _offered(&"gift")
	FixtureItemModes.stand(game, P2, Vector3(0, 0, FixtureHandOverModes.REACH_M + 0.1))
	_take_refused(game, P2, P1, TargetInReach.OUT_OF_REACH)
	var walled := FlatWorldQuery.new()
	var behind := _game(walled)
	_offer(behind, &"gift")
	# Opened in sight, then a wall comes between them (a door shut, a step round a corner).
	walled.add_wall(AABB(Vector3(-2, 0, 0.7), Vector3(4, 3, 0.1)))
	_take_refused(behind, P2, P1, TargetInSight.BLOCKED)


func test_the_givers_cancel_ends_it_and_the_item_stays() -> void:
	var game := _offered(&"gift")
	var gift: ItemState = game.state.items[game.state.player(P1).held_item]
	var seen := _counts(game)
	FixtureHandOverModes.cancel_offer(game, P1)
	_ended_once(game, seen)
	assert_int(gift.holder).is_equal(P1)
	FixtureHandOverModes.cancel_offer(game, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([Offers.NO_OFFER])
	_take_refused(game, P2, P1, Offers.NO_OFFER)


func test_the_item_leaving_the_hand_ends_it() -> void:
	var down := _offered(&"gift")
	FixtureItemModes.put_down(down, P1, Vector3(1, 0, 0))
	_ends_on_tick(down)
	var swapped := _offered(&"gift")
	FixtureItemModes.swap(swapped, P1)
	_take_refused(swapped, P2, P1, Offers.NO_OFFER)
	_ends_on_tick(swapped)
	var drawn := _offered(&"gift")
	FixtureItemModes.draw(drawn, P1, 1)
	_ends_on_tick(drawn)


func test_the_timeout_ends_it() -> void:
	var game := _offered(&"gift")
	var open := Ticks.from_seconds(FixtureHandOverModes.TIMEOUT_S)
	var opened := Offers.of_giver(game.state, P1).opened_tick
	FixtureModes.run_ticks(game, opened + open - 1 - game.ticked_through())
	assert_object(Offers.live(game.state, P1)).is_not_null()
	_ends_on_tick(game)


func test_either_side_walking_away_ends_it() -> void:
	for peer: int in [P1, P2]:
		var game := _offered(&"gift")
		var at := game.state.player(peer).position
		FixtureItemModes.stand(game, peer, at * 3.0 if peer == P2 else Vector3(0, 0, -1.0))
		_ends_on_tick(game)


func test_either_side_going_limp_downed_or_dead_ends_it() -> void:
	for peer: int in [P1, P2]:
		var limp := _offered(&"gift")
		FixtureHandOverModes.make_limp(limp, peer)
		_ends_on_tick(limp)
		for life: PlayerState.Life in [PlayerState.Life.DOWNED, PlayerState.Life.DEAD]:
			var game := _offered(&"gift")
			game.state.player(peer).life = life
			_ends_on_tick(game)


func test_either_side_leaving_ends_it() -> void:
	# A player gone gets no more events: the one who stays and the onlooker see the end.
	for peer: int in [P1, P2]:
		var game := _offered(&"gift")
		var seen := _counts(game)
		FixtureModes.send(game, Intents.PEER_LEFT, peer)
		FixtureModes.run_ticks(game, 1)
		var stays := P2 if peer == P1 else P1
		for watcher: int in [stays, P3]:
			var ended := FixtureItemModes.names_after(game, watcher, seen[watcher]).filter(
				func(name: StringName) -> bool: return name == &"OfferEnded"
			)
			assert_int(ended.size()).override_failure_message(str(peer)).is_equal(1)
		assert_object(Offers.of_giver(game.state, P1)).is_null()


func test_the_round_ending_ends_every_open_offer_in_giver_order() -> void:
	var game := _offered(&"gift")
	FixtureItemModes.stand(game, P3, Vector3(1.5, 0, 0))
	FixtureHandOverModes.hold(game, P3, &"cup")
	FixtureHandOverModes.hand_over(game, P3, P1)
	var seen := _counts(game)
	game.state.set_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	var ended := FixtureItemModes.names_after(game, P2, seen[P2]).filter(
		func(name: StringName) -> bool: return name == &"OfferEnded"
	)
	assert_int(ended.size()).is_equal(2)
	var events := game.view_of(P2).events_named(&"OfferEnded")
	assert_int((events[-2] as OfferEndedEvent).giver).is_equal(P1)
	assert_int((events[-1] as OfferEndedEvent).giver).is_equal(P3)
	assert_array(Offers.all(game.state)).is_empty()


## The hand-over mode in the round with P1 at the origin, P2 1.5 m away and P3 far off.
func _game(world: WorldQuery = null) -> Match:
	var game := FixtureItemModes.in_round(FixtureHandOverModes.basic(), [P1, P2, P3], world)
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, NEAR)
	FixtureItemModes.stand(game, P3, FAR)
	return game


## P1 holds an item of `kind_id` and offers it to P2.
func _offer(game: Match, kind_id: StringName) -> ItemState:
	var item := FixtureHandOverModes.hold(game, P1, kind_id)
	FixtureHandOverModes.hand_over(game, P1, P2)
	assert_object(Offers.live(game.state, P1)).is_not_null()
	return item


func _offered(kind_id: StringName) -> Match:
	var game := _game()
	_offer(game, kind_id)
	return game


## The next tick ends P1's offer: one OfferEnded (P1 to P2) to everyone; a later take is refused.
func _ends_on_tick(game: Match) -> void:
	var seen := _counts(game)
	FixtureModes.run_ticks(game, 1)
	_ended_once(game, seen)
	FixtureModes.run_ticks(game, 1)
	for peer: int in [P1, P2, P3]:
		var ended := game.view_of(peer).events_named(&"OfferEnded")
		assert_int(ended.size()).is_equal(1)


func _ended_once(game: Match, seen: Dictionary[int, int]) -> void:
	for peer: int in [P1, P2, P3]:
		var ended := FixtureItemModes.names_after(game, peer, seen[peer]).filter(
			func(name: StringName) -> bool: return name == &"OfferEnded"
		)
		assert_int(ended.size()).override_failure_message(str(peer)).is_equal(1)
		var last: OfferEndedEvent = game.view_of(peer).events_named(&"OfferEnded").back()
		assert_int(last.giver).is_equal(P1)
		assert_int(last.target).is_equal(P2)
	assert_object(Offers.of_giver(game.state, P1)).is_null()


## A TakeOffer from `peer` naming `giver` is refused with `reason` to `peer` alone; nothing moves.
func _take_refused(game: Match, peer: int, giver: int, reason: StringName) -> void:
	var before := FixtureHandOverModes.signature(game)
	var seen := _counts(game)
	FixtureHandOverModes.take_offer(game, peer, giver)
	var label := "%d %d %s" % [peer, giver, reason]
	(
		assert_array(FixtureItemModes.names_after(game, peer, seen[peer]))
		. override_failure_message(label)
		. is_equal([&"Rejected"])
	)
	assert_array(FixtureModes.rejections(game, peer).slice(-1)).is_equal([reason])
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
