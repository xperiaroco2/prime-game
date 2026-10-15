extends GdUnitTestSuite
## ClientModel's folds of Cooking's events (#776, the cooking ADR's §8 C7): OrderPosted and
## HerbsDealt on the places and the herbs, IngredientPlaced and GrillLoaded taking the item out of
## the putter's hand (the host sends no ItemPlaced for either), and a pickup, a put down or a throw
## clearing them again. Nothing kept names who put anything (the ADR's §3, "Who did it").

const C := preload("res://tests/fixtures/client/fixture_cooking_client.gd")

var _model: ClientModel


func before_test() -> void:
	_model = C.dealt(2)


func test_order_posted_and_herbs_dealt_fill_the_places_and_the_herbs() -> void:
	var place := _model.stations[C.FIRST_PLACE + 1]
	assert_str(String(place.bun)).is_equal("bun_a")
	assert_str(String(place.patty)).is_equal("fried_a")
	assert_int(place.icon).is_equal(1)
	assert_array(Array(_model.herb_code)).contains_exactly(["herb_a", "herb_b", "herb_c"])
	assert_array(Array(_model.herb_beds)).contains_exactly(["herb_a", "herb_b", "herb_c"])


func test_an_order_for_an_unknown_station_is_ignored() -> void:
	C.fold(_model, OrderPostedEvent.new(99, &"bun_b", &"fried_b", 2))
	assert_bool(_model.stations.has(99)).is_false()


func test_a_right_ingredient_leaves_the_hand_and_lies_locked_on_its_place() -> void:
	C.hold(_model, 50, &"bun_a")
	assert_int(_model.hand_item(C.OWN)).is_equal(50)
	C.put(_model, 50, 0, true)
	var item := _model.items[50]
	assert_int(_model.hand_item(C.OWN)).is_equal(-1)
	assert_int(item.holder).is_equal(ClientModel.NO_HOLDER)
	assert_int(item.on_station).is_equal(C.FIRST_PLACE)
	assert_bool(item.locked).is_true()
	assert_vector(item.position).is_equal(FixtureCookingModes.PLACE_SPOTS[0])
	assert_int(_model.stations[C.FIRST_PLACE].right_count).is_equal(1)
	assert_bool(_model.stations[C.FIRST_PLACE].done).is_false()


func test_a_wrong_ingredient_lies_on_its_place_unlocked_and_a_pickup_takes_it_back() -> void:
	C.hold(_model, 51, &"bun_b")
	C.put(_model, 51, 0, false)
	var item := _model.items[51]
	assert_int(item.on_station).is_equal(C.FIRST_PLACE)
	assert_bool(item.locked).is_false()
	assert_int(_model.stations[C.FIRST_PLACE].right_count).is_equal(0)
	C.fold(_model, ItemPickedUpEvent.new(C.OWN, 51))
	assert_int(item.on_station).is_equal(-1)
	assert_int(_model.hand_item(C.OWN)).is_equal(51)


func test_the_third_right_ingredient_finishes_the_place() -> void:
	var kinds: Array[StringName] = [&"bun_a", &"fried_a", &"herb_a"]
	for i in kinds.size():
		C.hold(_model, 60 + i, kinds[i])
		C.put(_model, 60 + i, 1, true)
	assert_int(_model.stations[C.FIRST_PLACE + 1].right_count).is_equal(ClientModel.ORDER_SLOTS)
	assert_bool(_model.stations[C.FIRST_PLACE + 1].done).is_true()
	assert_bool(_model.stations[C.FIRST_PLACE].done).is_false()


func test_a_grill_load_locks_the_patty_and_its_take_off_empties_the_grill() -> void:
	C.hold(_model, 70, &"raw_a")
	C.grill(_model, 70, 1200, 1300)
	var grill := _model.stations[C.GRILL]
	assert_int(grill.grill_item).is_equal(70)
	assert_int(grill.fried_tick).is_equal(1200)
	assert_int(grill.burnt_tick).is_equal(1300)
	assert_bool(_model.items[70].locked).is_true()
	assert_int(_model.items[70].on_station).is_equal(C.GRILL)
	assert_int(_model.hand_item(C.OWN)).is_equal(-1)
	C.fold(_model, ItemChangedEvent.new(70, &"fried_a"))
	assert_int(grill.grill_item).is_equal(70)
	# The take-off is a take (CD3 (b)): another player's ItemPickedUp.
	C.fold(_model, ItemPickedUpEvent.new(C.OTHER, 70))
	assert_int(grill.grill_item).is_equal(-1)
	assert_int(grill.fried_tick).is_equal(-1)
	assert_bool(_model.items[70].locked).is_false()
	assert_int(_model.items[70].on_station).is_equal(-1)


func test_a_take_off_onto_the_belt_also_empties_the_grill() -> void:
	C.hold(_model, 71, &"raw_a")
	C.grill(_model, 71, 1200, 1300)
	C.hold(_model, 72, &"package")
	C.fold(_model, ItemPickedUpEvent.new(C.OWN, 71, 71))
	assert_int(_model.stations[C.GRILL].grill_item).is_equal(-1)
	assert_bool(_model.items[71].belted).is_true()


func test_a_put_down_or_a_throw_clears_a_red_item() -> void:
	C.hold(_model, 80, &"herb_b")
	C.put(_model, 80, 0, false)
	C.fold(_model, ItemPickedUpEvent.new(C.OWN, 80))
	C.put(_model, 80, 0, false)
	C.fold(_model, ItemPlacedEvent.new(80, Vector3(1, 0, 1), Items.PUT_DOWN))
	assert_int(_model.items[80].on_station).is_equal(-1)


func test_a_mid_round_spawn_at_a_box_and_a_reused_id_are_new_items() -> void:
	C.spawn(_model, 90, &"bun_a", Vector3(20, 0, 40))
	assert_str(String(_model.items[90].kind)).is_equal("bun_a")
	assert_bool(_model.items[90].rests()).is_true()
	C.fold(_model, ItemVanishedEvent.new(90))
	assert_bool(_model.items.has(90)).is_false()
	C.spawn(_model, 90, &"herb_c", Vector3(6, 0, 20))
	assert_str(String(_model.items[90].kind)).is_equal("herb_c")
	assert_int(_model.items[90].on_station).is_equal(-1)


func test_clear_match_forgets_the_herbs() -> void:
	_model.clear_match()
	assert_int(_model.herb_code.size()).is_equal(0)
	assert_int(_model.herb_beds.size()).is_equal(0)


func test_no_kept_field_names_who_put_anything() -> void:
	# The same puts by two different peers leave the same state.
	var other := C.dealt(2)
	C.hold(_model, 50, &"bun_a", C.OWN)
	C.hold(other, 50, &"bun_a", C.OTHER)
	C.put(_model, 50, 0, true)
	C.put(other, 50, 0, true)
	C.hold(_model, 51, &"raw_a", C.OWN)
	C.hold(other, 51, &"raw_a", C.OTHER)
	C.grill(_model, 51, 1200, 1300)
	C.grill(other, 51, 1200, 1300)
	for id: int in [50, 51]:
		assert_dict(_fields(_model.items[id])).is_equal(_fields(other.items[id]))
	for id: int in [C.FIRST_PLACE, C.GRILL]:
		assert_dict(_fields(_model.stations[id])).is_equal(_fields(other.stations[id]))


func _fields(object: Object) -> Dictionary:
	var found := {}
	for property: Dictionary in object.get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			found[property["name"]] = object.get(property["name"] as String)
	return found
