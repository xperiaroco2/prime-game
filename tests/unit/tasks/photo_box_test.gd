extends GdUnitTestSuite
## The film box (the photo ADR §2.5, PE7, PE14, PD12; ARCHITECTURE §9.5): an Interact at the box
## gives the actor a new film through GiveItem.give_new (ItemSpawned at the box, then Items.give:
## into the hand, the hand item to the belt; beside a two-handed item onto the belt, a full belt's
## item down at the feet first; ItemPickedUp), nothing in the hands refusing it; its Cooldown
## refuses `too_soon` within its seconds, so one player's burst gets at most one film per 5 ticks
## at 0.25 s; it still gives once the task is done. GiveItem, Items.give and the belt move
## themselves are C1's and C2's to test. Fixture values only.

const P1 := 1
const P2 := 2
const P3 := 3
const PEERS: Array[int] = [P1, P2, P3]


func _round() -> Match:
	return FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS)


func _box(game: Match) -> int:
	return FixturePhotoModes.state_of(game).film_box


func test_a_take_puts_a_new_film_into_the_empty_hand() -> void:
	var game := _round()
	var seen := game.view_of(P2).events.size()
	FixturePhotoModes.use(game, P1, _box(game))
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"ItemSpawned", &"ItemPickedUp"]
	)
	var spawned: Dictionary = FixturePhotoModes.received(game, P2, &"ItemSpawned")[-1]
	assert_str(str(spawned["kind"])).is_equal("film")
	assert_vector(spawned["position"]).is_equal(FixturePhotoModes.BOX_AT)
	var film := Items.held_by(game.state, P1)
	assert_int(film.id).is_equal(spawned["item"])
	assert_object(FixturePhotoModes.state_of(game).film_of(film)).is_null()
	assert_array(FixturePhotoModes.reasons(game, P1)).is_empty()


func test_the_hands_knife_goes_to_the_belt() -> void:
	var game := _round()
	var knife := FixtureItemModes.lay(game, &"knife", Vector3(20, 0, 0))
	FixturePhotoModes.take(game, P1, knife)
	FixturePhotoModes.use(game, P1, _box(game))
	assert_str(Items.held_by(game.state, P1).kind.id).is_equal("film")
	assert_object(Items.belted_by(game.state, P1)).is_same(knife)


func test_a_package_carrier_gets_the_film_on_the_empty_belt() -> void:
	var game := _round()
	var package := FixtureItemModes.lay(game, &"package", Vector3(20, 0, 0))
	FixturePhotoModes.take(game, P1, package)
	FixturePhotoModes.use(game, P1, _box(game))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_empty()
	assert_object(Items.held_by(game.state, P1)).is_same(package)
	assert_str(Items.belted_by(game.state, P1).kind.id).is_equal("film")


func test_a_package_carriers_full_belt_puts_its_item_down_first() -> void:
	var game := _round()
	var knife := FixtureItemModes.lay(game, &"knife", Vector3(20, 0, 0))
	var package := FixtureItemModes.lay(game, &"package", Vector3(22, 0, 0))
	FixturePhotoModes.take(game, P1, knife)
	FixturePhotoModes.take(game, P1, package)
	# Both belt places full (GDD §6): the second goes onto the belt beside the package.
	FixturePhotoModes.take(game, P1, FixtureItemModes.lay(game, &"knife", Vector3(21, 0, 0)))
	assert_object(Items.belted_by(game.state, P1)).is_same(knife)
	var seen := game.view_of(P2).events.size()
	FixturePhotoModes.use(game, P1, _box(game))
	assert_array(_without_notes(FixtureItemModes.names_after(game, P2, seen))).is_equal(
		[&"ItemSpawned", &"ItemPlaced", &"ItemPickedUp"]
	)
	assert_int(knife.where).is_equal(ItemState.Where.GROUND)
	assert_object(Items.held_by(game.state, P1)).is_same(package)
	assert_str(Items.belted_by(game.state, P1).kind.id).is_equal("film")


func test_a_second_take_within_the_cooldown_is_too_soon() -> void:
	var game := _round()
	FixturePhotoModes.use(game, P1, _box(game), 1)
	FixturePhotoModes.use(game, P1, _box(game), 2)
	assert_array(FixturePhotoModes.reasons(game, P1)).is_equal([&"too_soon"])
	assert_array(FixturePhotoModes.received(game, P1, &"ItemPickedUp")).has_size(1)


func test_a_burst_over_100_ticks_gives_at_most_one_film_per_5_ticks() -> void:
	var game := _round()
	var seen := game.view_of(P2).events.size()
	for i in 100:
		FixturePhotoModes.use(game, P1, _box(game), i)
		FixtureModes.run_ticks(game, 1)
	var given := 0
	for event_name: StringName in FixtureItemModes.names_after(game, P2, seen):
		if event_name == &"ItemSpawned":
			given += 1
	assert_int(given).is_less_equal(100 / 5 + 1)
	assert_int(given).is_greater(1)
	assert_bool(FixturePhotoModes.reasons(game, P1).has(&"too_soon")).is_true()
	var films := 0
	for item: ItemState in game.state.items.values():
		if item.kind.id == &"film":
			films += 1
	assert_int(films).is_less_equal(game.mode.find_item_kind(&"film").max_items)


func test_the_box_still_gives_once_the_task_is_done() -> void:
	var game := _round()
	FixturePhotoModes.state_of(game).counted = PackedInt32Array([0, 1])
	FixturePhotoModes.use(game, P1, _box(game))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_empty()
	assert_str(Items.held_by(game.state, P1).kind.id).is_equal("film")


func test_a_take_from_out_of_reach_is_refused_and_gives_nothing() -> void:
	var game := _round()
	FixtureItemModes.stand(game, P1, FixturePhotoModes.BOX_AT + Vector3(0, 0, -5))
	FixtureStationModes.interact(game, P1, _box(game))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_equal([&"out_of_reach"])
	assert_object(Items.held_by(game.state, P1)).is_null()


## `names` without the fixture's FixtureNote (its rule notes an item coming to rest).
func _without_notes(names: Array[StringName]) -> Array[StringName]:
	return names.filter(func(name: StringName) -> bool: return name != &"FixtureNote")
