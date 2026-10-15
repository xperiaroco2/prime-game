extends GdUnitTestSuite
## CookingUse (client/world/cooking_use.gd; #776, the cooking ADR's §8 C7) through StationUse:
## which of Cooking's stations E offers, from the own ClientModel and the client's own copy of the
## mode only. Never a board; a place while not done and the hand holds a bun, a fried patty or a
## herb; the grill empty with a raw patty, occupied always; a bed always.

const C := preload("res://tests/fixtures/client/fixture_cooking_client.gd")

var _model: ClientModel
var _mode: GameMode


func before_test() -> void:
	_mode = FixtureCookingModes.basic(2)
	_model = C.dealt(2, _mode)


func test_the_roles_of_the_five_kinds() -> void:
	var type := FixtureCookingModes.type_of(_mode)
	assert_object(CookingUse.type_of(_mode, &"grill")).is_same(type)
	assert_int(CookingUse.role_of(type, &"order_board")).is_equal(CookingUse.Role.ORDER_BOARD)
	assert_int(CookingUse.role_of(type, &"herb_board")).is_equal(CookingUse.Role.HERB_BOARD)
	assert_int(CookingUse.role_of(type, &"grill")).is_equal(CookingUse.Role.GRILL)
	assert_int(CookingUse.role_of(type, &"herb_bed")).is_equal(CookingUse.Role.BED)
	assert_int(CookingUse.role_of(type, &"place")).is_equal(CookingUse.Role.PLACE)
	assert_int(CookingUse.role_of(type, &"knife")).is_equal(CookingUse.Role.NONE)
	assert_object(CookingUse.type_of(_mode, &"knife")).is_null()


func test_the_boards_are_never_offered_whatever_the_hand_holds() -> void:
	for kind: StringName in [&"", &"bun_a", &"raw_a"]:
		if kind != &"":
			C.hold(_model, 40 + kind.length(), kind)
		assert_bool(StationUse.usable(_model, _mode, C.ORDER_BOARD)).is_false()
		assert_bool(StationUse.usable(_model, _mode, C.HERB_BOARD)).is_false()


func test_a_board_given_a_rule_is_still_never_offered() -> void:
	# The display flag off and a use rule on: CookingUse itself refuses a board (CE6).
	var type := FixtureCookingModes.type_of(_mode)
	type.order_board.display = false
	type.order_board.actions = [FixtureStationModes.use_rule()]
	C.hold(_model, 41, &"bun_a")
	assert_bool(StationUse.usable(_model, _mode, C.ORDER_BOARD)).is_false()


func test_a_place_is_offered_for_a_bun_a_fried_patty_or_a_herb() -> void:
	var id := 50
	for kind: StringName in [&"bun_a", &"bun_b", &"fried_a", &"fried_b", &"herb_c"]:
		C.hold(_model, id, kind)
		(
			assert_bool(StationUse.usable(_model, _mode, C.FIRST_PLACE))
			. override_failure_message("a place refused %s" % kind)
			. is_true()
		)
		C.put(_model, id, 1, false)
		id += 1


func test_a_place_is_not_offered_for_a_raw_or_burnt_patty_a_knife_or_empty_hands() -> void:
	assert_bool(StationUse.usable(_model, _mode, C.FIRST_PLACE)).is_false()
	var id := 50
	for kind: StringName in [&"raw_a", &"burnt", &"knife"]:
		C.hold(_model, id, kind)
		(
			assert_bool(StationUse.usable(_model, _mode, C.FIRST_PLACE))
			. override_failure_message("a place took %s" % kind)
			. is_false()
		)
		C.fold(_model, ItemPlacedEvent.new(id, Vector3.ZERO, Items.PUT_DOWN))
		id += 1


func test_a_done_place_is_not_offered() -> void:
	var kinds: Array[StringName] = [&"bun_a", &"fried_a", &"herb_a"]
	for i in kinds.size():
		C.hold(_model, 60 + i, kinds[i])
		C.put(_model, 60 + i, 0, true)
	C.hold(_model, 63, &"bun_b")
	assert_bool(StationUse.usable(_model, _mode, C.FIRST_PLACE)).is_false()
	assert_bool(StationUse.usable(_model, _mode, C.FIRST_PLACE + 1)).is_true()


func test_a_two_handed_box_in_the_hand_offers_no_place() -> void:
	C.hold(_model, 64, &"box_bun_a")
	assert_bool(StationUse.usable(_model, _mode, C.FIRST_PLACE)).is_false()


func test_the_empty_grill_wants_a_raw_patty_and_the_occupied_one_is_always_offered() -> void:
	assert_bool(StationUse.usable(_model, _mode, C.GRILL)).is_false()
	C.hold(_model, 70, &"fried_a")
	assert_bool(StationUse.usable(_model, _mode, C.GRILL)).is_false()
	C.hold(_model, 71, &"raw_b", C.OTHER)
	C.grill(_model, 71, 1200, 1300)
	# Occupied: the take-off is offered whatever the hand holds, a box too (CD3 (b)).
	assert_bool(StationUse.usable(_model, _mode, C.GRILL)).is_true()
	C.fold(_model, ItemPickedUpEvent.new(C.OTHER, 71))
	assert_bool(StationUse.usable(_model, _mode, C.GRILL)).is_false()
	C.fold(_model, ItemPlacedEvent.new(70, Vector3.ZERO, Items.PUT_DOWN))
	C.hold(_model, 72, &"raw_a")
	assert_bool(StationUse.usable(_model, _mode, C.GRILL)).is_true()


func test_a_bed_is_always_offered_with_a_one_handed_hand() -> void:
	for i in FixtureCookingModes.BED_SPOTS.size():
		assert_bool(StationUse.usable(_model, _mode, C.FIRST_BED + i)).is_true()
	C.hold(_model, 73, &"box_raw_a")
	# A bed's rule has no HandNotTwoHanded (a take beside a box, CD3 (b)).
	assert_bool(StationUse.usable(_model, _mode, C.FIRST_BED)).is_true()


func test_a_box_is_an_item_with_a_take_and_an_ingredient_is_not() -> void:
	assert_bool(CookingUse.is_box(_mode, &"box_bun_a")).is_true()
	assert_bool(CookingUse.is_box(_mode, &"bun_a")).is_false()
	assert_bool(CookingUse.is_box(_mode, &"nothing")).is_false()


func test_place_numbers_follow_the_station_order() -> void:
	var type := FixtureCookingModes.type_of(_mode)
	assert_int(CookingUse.place_number(_model, type, C.FIRST_PLACE)).is_equal(1)
	assert_int(CookingUse.place_number(_model, type, C.FIRST_PLACE + 1)).is_equal(2)
	assert_int(CookingUse.place_number(_model, type, C.GRILL)).is_equal(0)
	assert_array(CookingUse.stations_of(_model, type, CookingUse.Role.BED)).contains_exactly(
		[C.FIRST_BED, C.FIRST_BED + 1, C.FIRST_BED + 2]
	)


func test_the_plate_slot_of_each_ingredient_group() -> void:
	var type := FixtureCookingModes.type_of(_mode)
	assert_int(CookingUse.slot_of(type, &"bun_b")).is_equal(0)
	for kind: StringName in [&"raw_a", &"fried_b", &"burnt"]:
		assert_int(CookingUse.slot_of(type, kind)).is_equal(1)
	assert_int(CookingUse.slot_of(type, &"herb_b")).is_equal(2)
	assert_int(CookingUse.slot_of(type, &"knife")).is_equal(-1)
