extends GdUnitTestSuite
## CarRepairUse (client/world/car_repair_use.gd; #811, the car repair ADR's §8 R7) through
## StationUse: which of the car repair's stations E offers, from the own ClientModel and the
## client's own copy of the mode only, and the car's height from LiftChanged's ticks.

const C := preload("res://tests/fixtures/client/fixture_car_repair_client.gd")
## FixtureCarRepairModes' RISE_TICKS (0.5 s).
const RISE := FixtureCarRepairModes.RISE_TICKS

var _model: ClientModel
var _mode: GameMode
var _type: CarRepair


func before_test() -> void:
	_mode = FixtureCarRepairModes.basic()
	_type = FixtureCarRepairModes.type_of(_mode)
	_model = C.dealt(_mode)


func test_the_roles_of_the_kinds() -> void:
	assert_object(CarRepairUse.type_of(_mode, &"car")).is_same(_type)
	assert_int(CarRepairUse.role_of(_type, &"car")).is_equal(CarRepairUse.Role.CAR)
	assert_int(CarRepairUse.role_of(_type, &"lift_panel")).is_equal(CarRepairUse.Role.PANEL)
	assert_int(CarRepairUse.role_of(_type, &"bin_filter")).is_equal(CarRepairUse.Role.BIN)
	assert_int(CarRepairUse.role_of(_type, &"part_picture")).is_equal(CarRepairUse.Role.PICTURE)
	assert_int(CarRepairUse.role_of(_type, &"knife")).is_equal(CarRepairUse.Role.NONE)
	assert_object(CarRepairUse.type_of(_mode, &"knife")).is_null()
	assert_object(CarRepairUse.type_of(FixtureCookingModes.basic(1), &"grill")).is_null()


func test_the_panel_is_offered_until_someone_holds_or_the_task_is_done() -> void:
	assert_bool(StationUse.usable(_model, _mode, C.PANEL)).is_true()
	C.lift(_model, true, 100)
	assert_bool(StationUse.usable(_model, _mode, C.PANEL)).is_false()
	C.lift(_model, false, 120)
	assert_bool(StationUse.usable(_model, _mode, C.PANEL)).is_true()
	C.fold(_model, TaskStateEvent.new(C.TASK, &"car_repair", 3, 3))
	assert_bool(StationUse.usable(_model, _mode, C.PANEL)).is_false()


func test_the_panel_reads_nothing_of_the_fit() -> void:
	# RE16, RD14 (a): a fit running, stopped or completed changes nothing the panel offers.
	C.hold(_model, 40, &"spark_plug", C.OTHER)
	C.fold(_model, FitChangedEvent.new(C.CAR, C.OTHER, 130))
	assert_bool(StationUse.usable(_model, _mode, C.PANEL)).is_true()
	C.fold(_model, PartFittedEvent.new(C.CAR, 40))
	assert_bool(StationUse.usable(_model, _mode, C.PANEL)).is_true()


func test_the_car_is_offered_only_fully_up_with_the_needed_part_and_nobody_fitting() -> void:
	C.hold(_model, 40, &"spark_plug")
	C.at_tick(_model, 200)
	# Down.
	assert_bool(StationUse.usable(_model, _mode, C.CAR)).is_false()
	C.lift(_model, true, 195)
	# Going up, not fully up yet.
	assert_bool(StationUse.usable(_model, _mode, C.CAR)).is_false()
	C.at_tick(_model, 195 + RISE)
	assert_bool(StationUse.usable(_model, _mode, C.CAR)).is_true()
	# Someone else fits.
	C.fold(_model, FitChangedEvent.new(C.CAR, C.OTHER, 206))
	assert_bool(StationUse.usable(_model, _mode, C.CAR)).is_false()
	C.fold(_model, FitChangedEvent.new(C.CAR, 0, 207))
	assert_bool(StationUse.usable(_model, _mode, C.CAR)).is_true()
	# The car comes down.
	C.lift(_model, false, 208)
	assert_bool(StationUse.usable(_model, _mode, C.CAR)).is_false()


func test_the_car_is_not_offered_for_a_wrong_part_empty_hands_or_a_done_task() -> void:
	C.lift(_model, true, 100)
	C.at_tick(_model, 100 + RISE)
	assert_bool(StationUse.usable(_model, _mode, C.CAR)).is_false()
	C.hold(_model, 41, &"filter")
	assert_bool(StationUse.usable(_model, _mode, C.CAR)).is_false()
	C.fold(_model, PartNeededEvent.new(C.PICTURE, &"filter"))
	assert_bool(StationUse.usable(_model, _mode, C.CAR)).is_true()
	C.fold(_model, TaskStateEvent.new(C.TASK, &"car_repair", 3, 3))
	assert_bool(StationUse.usable(_model, _mode, C.CAR)).is_false()


func test_the_car_is_not_offered_without_an_estimated_host_tick() -> void:
	# A client that draws nothing (a bot, a unit test) cannot tell the car is fully up.
	C.hold(_model, 40, &"spark_plug")
	C.lift(_model, true, 0)
	assert_bool(_model.host_tick_now.is_valid()).is_false()
	assert_bool(StationUse.usable(_model, _mode, C.CAR)).is_false()


func test_a_two_handed_hand_is_refused_at_the_car_and_the_panel() -> void:
	var package := FixtureItemModes.item_kind(&"package", [])
	package.hands = 2
	_mode.item_kinds.append(package)
	C.hold(_model, 42, &"package")
	C.lift(_model, true, 100)
	C.at_tick(_model, 100 + RISE)
	assert_bool(StationUse.usable(_model, _mode, C.CAR)).is_false()
	C.lift(_model, false, 120)
	assert_bool(StationUse.usable(_model, _mode, C.PANEL)).is_false()


func test_a_bin_is_always_offered_and_the_picture_never() -> void:
	for i in FixtureCarRepairModes.PARTS.size():
		assert_bool(StationUse.usable(_model, _mode, C.FIRST_BIN + i)).is_true()
	assert_bool(StationUse.usable(_model, _mode, C.PICTURE)).is_false()
	C.fold(_model, TaskStateEvent.new(C.TASK, &"car_repair", 3, 3))
	assert_bool(StationUse.usable(_model, _mode, C.FIRST_BIN)).is_true()


func test_the_panel_and_the_car_hold_and_a_bin_does_not() -> void:
	assert_bool(StationUse.holds(_mode, &"lift_panel")).is_true()
	assert_bool(StationUse.holds(_mode, &"car")).is_true()
	assert_bool(StationUse.holds(_mode, &"bin_filter")).is_false()
	assert_bool(StationUse.holds(_mode, &"part_picture")).is_false()
	assert_bool(StationUse.holds(_mode, &"nothing")).is_false()


func test_the_lift_rises_holds_and_drops_from_the_height_it_reached() -> void:
	var panel := _model.stations[C.PANEL]
	var drop := 4
	assert_float(CarRepairUse.lift_fraction(panel, 50.0, RISE, drop)).is_equal(0.0)
	C.lift(_model, true, 100)
	assert_float(CarRepairUse.lift_fraction(panel, 100.0, RISE, drop)).is_equal(0.0)
	assert_float(CarRepairUse.lift_fraction(panel, 105.0, RISE, drop)).is_equal_approx(0.5, 1e-6)
	assert_float(CarRepairUse.lift_fraction(panel, 102.5, RISE, drop)).is_equal_approx(0.25, 1e-6)
	assert_float(CarRepairUse.lift_fraction(panel, 110.0, RISE, drop)).is_equal(1.0)
	assert_float(CarRepairUse.lift_fraction(panel, 400.0, RISE, drop)).is_equal(1.0)
	assert_bool(CarRepairUse.rising(panel, 105.0, RISE)).is_true()
	assert_bool(CarRepairUse.rising(panel, 110.0, RISE)).is_false()
	assert_bool(CarRepairUse.is_up(_model, _type, 109.0)).is_false()
	assert_bool(CarRepairUse.is_up(_model, _type, 110.0)).is_true()
	# Dropped from fully up: down over the drop's ticks.
	C.lift(_model, false, 400)
	assert_bool(CarRepairUse.rising(panel, 401.0, RISE)).is_false()
	assert_bool(CarRepairUse.is_up(_model, _type, 401.0)).is_false()
	assert_float(CarRepairUse.lift_fraction(panel, 400.0, RISE, drop)).is_equal(1.0)
	assert_float(CarRepairUse.lift_fraction(panel, 402.0, RISE, drop)).is_equal_approx(0.5, 1e-6)
	assert_float(CarRepairUse.lift_fraction(panel, 404.0, RISE, drop)).is_equal(0.0)
	# Dropped halfway up: from half its height.
	C.lift(_model, true, 500)
	C.lift(_model, false, 505)
	assert_float(CarRepairUse.lift_fraction(panel, 505.0, RISE, drop)).is_equal_approx(0.5, 1e-6)
	assert_float(CarRepairUse.lift_fraction(panel, 507.0, RISE, drop)).is_equal_approx(0.25, 1e-6)
	assert_float(CarRepairUse.lift_fraction(panel, 600.0, RISE, drop)).is_equal(0.0)


func test_the_fit_progress_is_the_own_fitter_s_alone() -> void:
	var ticks := CarRepairUse.fit_ticks(_type)
	assert_int(ticks).is_equal(Ticks.from_seconds(FixtureCarRepairModes.FIT_SECONDS))
	assert_float(CarRepairUse.fit_progress(_model, _type, 10.0)).is_equal(-1.0)
	C.fold(_model, FitChangedEvent.new(C.CAR, C.OTHER, 100))
	assert_float(CarRepairUse.fit_progress(_model, _type, 105.0)).is_equal(-1.0)
	C.fold(_model, FitChangedEvent.new(C.CAR, C.OWN, 200))
	assert_float(CarRepairUse.fit_progress(_model, _type, 200.0)).is_equal(0.0)
	var half := 200.0 + ticks / 2.0
	assert_float(CarRepairUse.fit_progress(_model, _type, half)).is_equal_approx(0.5, 1e-6)
	assert_float(CarRepairUse.fit_progress(_model, _type, 900.0)).is_equal(1.0)
	C.fold(_model, FitChangedEvent.new(C.CAR, 0, 210))
	assert_float(CarRepairUse.fit_progress(_model, _type, 211.0)).is_equal(-1.0)
