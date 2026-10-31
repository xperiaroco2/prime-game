extends GdUnitTestSuite
## Items.give (ARCHITECTURE §9.3; the cooking ADR §2's table, CD3 (b), CD5 (b), CE19, CE20): an
## item a source hands out goes to the taker, who makes room: empty hands take it into the hand; a
## one-handed hand item moves to an empty belt, or with a full belt is put down at the taker's feet
## (ItemPlaced `put_down`, item_rested) before ItemPickedUp; beside a two-handed hand item the new
## item goes onto the belt (`belted` the item itself), a full belt's item put down at the feet
## first, and the two-handed item stays in the hand. Driven by Use through FixtureItemMove's GIVE
## (a box's take stand-in) on a seeded fixture match; asserted on the events, view_of and the state.
## Items.hand_out (#1461) through HAND_OUT_AT: a two-handed item, locked at a source, into the hand
## by take()'s hand rules; a one-handed one as give() does.

const P1 := 1
const P2 := 2
## Where P1 stands; the feet a displaced item is put down at on the flat fixture world.
const FEET := Vector3(0.5, 0, 0.25)
## The source's spot (a box's position).
const SOURCE := Vector3(1, 0, 1)


func test_empty_hands_take_it_into_the_hand() -> void:
	var game := _game()
	var seen := game.view_of(P2).events.size()
	FixtureItemMove.use(game, P1, FixtureItemMove.GIVE, SOURCE, &"herb")
	var herb := _newest(game)
	var player := game.state.player(P1)
	assert_int(player.held_item).is_equal(herb.id)
	assert_int(player.belt_item).is_equal(-1)
	assert_int(herb.where).is_equal(ItemState.Where.HAND)
	assert_int(herb.holder).is_equal(P1)
	assert_int(herb.rest_tick).is_equal(-1)
	# The new item never rested: no item_rested for it, no ItemPlaced.
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemSpawned", &"ItemPickedUp"]
	)
	assert_dict(_last_pick(game, P2).to_dict()).is_equal(
		{"peer": P1, "item": herb.id, "belted": -1, "place": 0}
	)
	assert_array(FixtureModes.notes(game)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_one_handed_hand_item_moves_to_an_empty_belt() -> void:
	var game := _game()
	var hand := _picked(game, &"herb")
	var seen := game.view_of(P2).events.size()
	FixtureItemMove.use(game, P1, FixtureItemMove.GIVE, SOURCE, &"herb")
	var herb := _newest(game)
	var player := game.state.player(P1)
	assert_int(player.held_item).is_equal(herb.id)
	assert_int(player.belt_item).is_equal(hand.id)
	assert_int(hand.where).is_equal(ItemState.Where.BELT)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemSpawned", &"ItemPickedUp"]
	)
	assert_dict(_last_pick(game, P2).to_dict()).is_equal(
		{"peer": P1, "item": herb.id, "belted": hand.id, "place": 1}
	)


func test_with_a_full_belt_the_hand_item_is_put_down_at_the_feet_first() -> void:
	var game := _game()
	var belted := _picked(game, &"tool")
	# A full belt: both belt places taken (GDD §6).
	_picked(game, &"tool")
	var held := _picked(game, &"herb")
	assert_int(belted.where).is_equal(ItemState.Where.BELT)
	var seen := game.view_of(P2).events.size()
	var tick := game.ticked_through() + 1
	# A Use with a herb in the hand reaches the mode's rule (the herb has no actions).
	FixtureItemMove.use(game, P1, FixtureItemMove.GIVE, SOURCE, &"herb")
	var given := _newest(game)
	var player := game.state.player(P1)
	assert_int(player.held_item).is_equal(given.id)
	assert_int(player.belt_item).is_equal(belted.id)
	assert_int(held.where).is_equal(ItemState.Where.GROUND)
	assert_int(held.holder).is_equal(0)
	assert_vector(held.position).is_equal(FEET)
	# Laid through Items.lay: it lies from this tick (VanishTicks counts from here).
	assert_int(held.rest_tick).is_equal(tick)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemSpawned", &"ItemPlaced", &"FixtureNote", &"FixtureNote", &"ItemPickedUp"]
	)
	var placed := game.view_of(P2).events_named(&"ItemPlaced")[0] as ItemPlacedEvent
	assert_dict(placed.to_dict()).is_equal(
		{"item": held.id, "position": FEET, "cause": &"put_down"}
	)
	assert_dict(_last_pick(game, P2).to_dict()).is_equal(
		{"peer": P1, "item": given.id, "belted": -1, "place": 2}
	)
	assert_array(FixtureModes.notes(game)).is_equal(
		[FixtureRestedNote.text(held.id, &"put_down", FEET), "task item_rested"]
	)


func test_beside_a_two_handed_hand_item_it_goes_onto_the_empty_belt() -> void:
	var game := _game()
	var package := _picked(game, &"package")
	var seen := game.view_of(P2).events.size()
	FixtureItemMove.use(game, P1, FixtureItemMove.GIVE, SOURCE, &"herb")
	var herb := _newest(game)
	var player := game.state.player(P1)
	assert_int(player.held_item).is_equal(package.id)
	assert_int(player.belt_item).is_equal(herb.id)
	assert_int(package.where).is_equal(ItemState.Where.HAND)
	assert_int(herb.where).is_equal(ItemState.Where.BELT)
	assert_int(herb.holder).is_equal(P1)
	assert_int(herb.rest_tick).is_equal(-1)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemSpawned", &"ItemPickedUp"]
	)
	assert_dict(_last_pick(game, P2).to_dict()).is_equal(
		{"peer": P1, "item": herb.id, "belted": herb.id, "place": 1}
	)


func test_beside_a_two_handed_hand_item_a_full_belt_s_item_goes_down_at_the_feet_first() -> void:
	var game := _game()
	var belted := _picked(game, &"tool")
	# A full belt: both belt places taken (GDD §6).
	_picked(game, &"tool")
	var package := _picked(game, &"package")
	assert_int(belted.where).is_equal(ItemState.Where.BELT)
	var seen := game.view_of(P2).events.size()
	FixtureItemMove.use(game, P1, FixtureItemMove.GIVE, SOURCE, &"herb")
	var herb := _newest(game)
	var player := game.state.player(P1)
	assert_int(player.held_item).is_equal(package.id)
	assert_int(player.belt_item).is_equal(herb.id)
	assert_int(belted.where).is_equal(ItemState.Where.GROUND)
	assert_vector(belted.position).is_equal(FEET)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemSpawned", &"ItemPlaced", &"FixtureNote", &"FixtureNote", &"ItemPickedUp"]
	)
	var placed := game.view_of(P2).events_named(&"ItemPlaced")[0] as ItemPlacedEvent
	assert_dict(placed.to_dict()).is_equal(
		{"item": belted.id, "position": FEET, "cause": &"put_down"}
	)
	assert_dict(_last_pick(game, P2).to_dict()).is_equal(
		{"peer": P1, "item": herb.id, "belted": herb.id, "place": 0}
	)
	# The taker learns the same public events.
	assert_array(game.view_of(P1).events_named(&"ItemPickedUp")).has_size(4)


func test_a_two_handed_given_item_is_a_rule_error_and_nothing_moves() -> void:
	var game := _game()
	var hand := _picked(game, &"herb")
	FixtureItemMove.use(game, P1, FixtureItemMove.GIVE, SOURCE, &"package")
	var package := _newest(game)
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_int(game.state.player(P1).held_item).is_equal(hand.id)
	assert_array(Array(game.diagnostics)).is_not_empty()
	assert_str(game.diagnostics[0]).contains("two-handed")


func _game() -> Match:
	var game := FixtureItemModes.in_round(FixtureItemMove.mode(), [P1, P2])
	FixtureItemModes.stand(game, P1, FEET)
	return game


## An item of `kind_id` laid next to P1 and picked up by it.
func _picked(game: Match, kind_id: StringName) -> ItemState:
	var item := FixtureItemModes.lay(game, kind_id, FEET + Vector3(0, 0, 1))
	FixtureItemModes.pick_up(game, P1, item)
	return item


## The item with the highest id: the one a GIVE just spawned.
func _newest(game: Match) -> ItemState:
	var found: ItemState = null
	for item: ItemState in game.state.items.values():
		if found == null or item.id > found.id:
			found = item
	return found


func _last_pick(game: Match, peer: int) -> ItemPickedUpEvent:
	return game.view_of(peer).events_named(&"ItemPickedUp")[-1] as ItemPickedUpEvent


func test_hand_out_puts_a_locked_two_handed_item_into_empty_hands() -> void:
	var game := _game()
	var package := _locked(game, &"package")
	var seen := game.view_of(P2).events.size()
	FixtureItemMove.use(game, P1, FixtureItemMove.HAND_OUT_AT, SOURCE)
	assert_int(game.state.player(P1).held_item).is_equal(package.id)
	assert_int(package.where).is_equal(ItemState.Where.HAND)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal([&"ItemPickedUp"])
	assert_array(Array(game.diagnostics)).is_empty()


func test_hand_out_puts_a_one_handed_hand_item_onto_the_belt_for_a_two_handed_one() -> void:
	var game := _game()
	var hand := _picked(game, &"herb")
	var package := _locked(game, &"package")
	FixtureItemMove.use(game, P1, FixtureItemMove.HAND_OUT_AT, SOURCE)
	var player := game.state.player(P1)
	assert_int(player.held_item).is_equal(package.id)
	assert_int(player.belt_item).is_equal(hand.id)
	assert_array(Array(game.diagnostics)).is_empty()


func test_hand_out_swaps_a_two_handed_hand_item_out_at_the_feet() -> void:
	var game := _game()
	var hand := _picked(game, &"package")
	var package := _locked(game, &"package")
	var seen := game.view_of(P2).events.size()
	FixtureItemMove.use(game, P1, FixtureItemMove.HAND_OUT_AT, SOURCE)
	assert_int(game.state.player(P1).held_item).is_equal(package.id)
	assert_int(hand.where).is_equal(ItemState.Where.GROUND)
	# The swapped item rests (item_rested: FixtureNote rows after the two moves).
	assert_array(FixtureItemModes.names_after(game, P2, seen).slice(0, 2)).is_equal(
		[&"ItemPickedUp", &"ItemPlaced"]
	)
	var placed := game.view_of(P2).events_named(&"ItemPlaced")[-1].to_dict()
	assert_int(placed["item"]).is_equal(hand.id)
	assert_str(str(placed["cause"])).is_equal(String(Items.SWAP))


func test_hand_out_gives_a_one_handed_item_as_give_does() -> void:
	var game := _game()
	var herb := FixtureItemModes.lay(game, &"herb", SOURCE)
	FixtureItemMove.use(game, P1, FixtureItemMove.HAND_OUT_AT, SOURCE)
	assert_int(game.state.player(P1).held_item).is_equal(herb.id)
	assert_array(Array(game.diagnostics)).is_empty()


## An item of `kind_id` locked at SOURCE (a station's, as the crystal in its charger).
func _locked(game: Match, kind_id: StringName) -> ItemState:
	var item := FixtureItemModes.lay(game, kind_id, SOURCE)
	Items.lock(item)
	return item
