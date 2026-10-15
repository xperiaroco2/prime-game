extends GdUnitTestSuite
## TargetChoice over Cooking (client/world/target_choice.gd; #776, the cooking ADR's §8 C7), pure:
## a board is never named; a place only for what it takes; a locked item (a right ingredient, the
## grill's patty) is never picked; a wrong one on a plate is aimed at where the plate draws it
## (`aim_of`), never at its floor point, and loses to the place when the hand holds what the place
## takes. FixtureCookingClient: place 0's floor point at (0, 0, 30).

const C := preload("res://tests/fixtures/client/fixture_cooking_client.gd")
const FEET := Vector3(0, 0, 29.5)
const EYE := Vector3(0, 1.6, 29.5)
## Where the plate draws a wrong item of place 0 (a stand-in for CookingViews.aim_of).
const ON_PLATE := Vector3(0, 0.9, 30.4)
const NO_DEVICE := -1

var _model: ClientModel
var _mode: GameMode


func before_test() -> void:
	_mode = FixtureCookingModes.basic(2)
	_model = C.dealt(2, _mode)


func test_a_board_is_never_named_at_its_device_or_its_spot() -> void:
	var feet := FixtureCookingModes.ORDER_BOARD_AT + Vector3(0, 0, -0.5)
	var eye := feet + Vector3.UP * 1.6
	var spot := TargetChoice.aim_point(_model.stations[C.ORDER_BOARD])
	var look := (spot - eye).normalized()
	var target := TargetChoice.choose_target(
		_model, _mode, eye, look, 1.0, feet, _reach(), C.ORDER_BOARD
	)
	assert_int(target.kind).is_equal(TargetChoice.Target.Kind.NONE)


func test_a_place_is_named_with_a_bun_in_the_hand_and_not_with_a_raw_patty() -> void:
	C.hold(_model, 50, &"bun_a")
	assert_bool(_at_place().is_station()).is_true()
	assert_int(_at_place().id).is_equal(C.FIRST_PLACE)
	C.fold(_model, ItemPlacedEvent.new(50, Vector3(5, 0, 5), Items.PUT_DOWN))
	C.hold(_model, 51, &"raw_a")
	assert_int(_at_place().kind).is_equal(TargetChoice.Target.Kind.NONE)


func test_a_locked_item_on_a_plate_is_never_picked() -> void:
	C.hold(_model, 52, &"bun_a")
	C.put(_model, 52, 0, true)
	var look := (ON_PLATE - EYE).normalized()
	assert_int(_choose(look)).is_equal(-1)


func test_a_wrong_item_is_aimed_on_the_plate_and_not_at_its_floor_point() -> void:
	C.hold(_model, 53, &"bun_b")
	C.put(_model, 53, 0, false)
	var at_plate := (ON_PLATE - EYE).normalized()
	var target := TargetChoice.choose_target(
		_model, _mode, EYE, at_plate, TargetChoice.RAY_M, FEET, _reach(), NO_DEVICE, _aim
	)
	assert_bool(target.is_item()).is_true()
	assert_int(target.id).is_equal(53)
	# Its floor point (the use spot the host measures reach from) names nothing.
	var at_floor := (FixtureCookingModes.PLACE_SPOTS[0] - EYE).normalized()
	assert_int(TargetChoice.along_ray(_model, EYE, at_floor, TargetChoice.RAY_M, _aim)).is_equal(-1)
	# With no plate view to aim at, it is never named.
	assert_int(TargetChoice.along_ray(_model, EYE, at_plate, TargetChoice.RAY_M)).is_equal(-1)


func test_the_place_wins_over_a_wrong_item_when_the_hand_holds_what_it_takes() -> void:
	C.hold(_model, 54, &"bun_b")
	C.put(_model, 54, 0, false)
	C.hold(_model, 55, &"fried_a")
	var at_plate := (ON_PLATE - EYE).normalized()
	# The ray meets the counter (the place's device) just behind the plate item.
	var target := TargetChoice.choose_target(
		_model,
		_mode,
		EYE,
		at_plate,
		EYE.distance_to(ON_PLATE) + 0.3,
		FEET,
		_reach(),
		C.FIRST_PLACE,
		_aim
	)
	assert_bool(target.is_station()).is_true()
	assert_int(target.id).is_equal(C.FIRST_PLACE)


func test_a_box_on_the_ground_is_picked_as_any_item() -> void:
	C.spawn(_model, 56, &"box_bun_a", Vector3(0, 0, 30.8))
	var look := (ItemView.centre_of(&"box_bun_a", Vector3(0, 0, 30.8)) - EYE).normalized()
	assert_int(_choose(look)).is_equal(56)


func _aim(id: int) -> Variant:
	return ON_PLATE if _model.items[id].on_station == C.FIRST_PLACE else null


func _reach() -> float:
	return TargetChoice.hint_reach_of(_mode)


func _choose(look: Vector3) -> int:
	return TargetChoice.choose(_model, EYE, look, TargetChoice.RAY_M, FEET, _reach(), _aim)


func _at_place() -> TargetChoice.Target:
	var look := (TargetChoice.aim_point(_model.stations[C.FIRST_PLACE]) - EYE).normalized()
	return TargetChoice.choose_target(
		_model, _mode, EYE, look, TargetChoice.RAY_M, FEET, _reach(), NO_DEVICE, _aim
	)
