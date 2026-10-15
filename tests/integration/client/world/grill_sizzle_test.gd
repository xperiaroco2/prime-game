extends GdUnitTestSuite
## Cooking's grill sizzle (#776, the cooking ADR's CD14 (a); StationHums): a patty on the grill
## sizzles while it fries (CookingViews.ring_phase at the estimated host tick), on a looping
## placeholder with the hearing range as max_distance, and stops once it is fried (CD14 (a): "a
## sizzle while a patty fries", then a ding) or taken off, and when the round ends; never beyond the
## hearing range.

const C := preload("res://tests/fixtures/client/fixture_cooking_client.gd")
const NEAR := FixtureCookingModes.GRILL_AT + Vector3(0, 1.5, -5)
const FAR := FixtureCookingModes.GRILL_AT + Vector3(0, 1.5, -SoundChooser.HEARING_RANGE_M - 1)

var _world: Node3D
var _hums: StationHums
var _ears := NEAR
var _now := 1000
var _model: ClientModel


func before_test() -> void:
	AudioBuses.ensure()
	_ears = NEAR
	_now = 1000
	_world = Node3D.new()
	add_child(_world)
	_hums = StationHums.new()
	_hums.ears = func() -> Variant: return _ears
	_hums.host_tick = func() -> int: return _now
	_world.add_child(_hums)
	var mode := FixtureCookingModes.basic(2)
	_model = C.dealt(2, mode)
	_hums.model = _model
	_hums.mode = mode


func after_test() -> void:
	_world.free()


func test_a_patty_sizzles_while_it_fries_and_stops_once_fried() -> void:
	await _frames()
	assert_int(_hums.hums()).is_equal(0)
	_load()
	await _frames()
	assert_int(_hums.hums()).is_equal(1)
	var sizzle := _hums.hum_of(C.GRILL)
	assert_str(String(sizzle.name)).is_equal("Sizzle%d" % C.GRILL)
	assert_bool(sizzle.playing).is_true()
	assert_float(sizzle.max_distance).is_equal(SoundChooser.HEARING_RANGE_M)
	assert_that(sizzle.position).is_equal(FixtureCookingModes.GRILL_AT)
	assert_int((sizzle.stream as AudioStreamWAV).loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	_now = 1099
	await _frames()
	assert_int(_hums.hums()).is_equal(1)
	_now = 1100
	await _frames()
	assert_int(_hums.hums()).is_equal(0)
	_now = 1150
	await _frames()
	assert_int(_hums.hums()).is_equal(0)
	_now = 1200
	await _frames()
	assert_int(_hums.hums()).is_equal(0)


func test_taking_the_patty_off_stops_the_sizzle() -> void:
	_load()
	await _frames()
	assert_int(_hums.hums()).is_equal(1)
	_model.fold(&"ItemPickedUp", {"peer": C.OWN, "item": 60})
	await _frames()
	assert_int(_hums.hums()).is_equal(0)


func test_the_round_ending_stops_the_sizzle() -> void:
	_load()
	await _frames()
	_model.fold(&"MatchEnded", {"side": &"crew"})
	await _frames()
	assert_int(_hums.hums()).is_equal(0)


func test_beyond_the_hearing_range_no_sizzle_starts() -> void:
	_ears = FAR
	_load()
	await _frames()
	assert_int(_hums.started()).is_equal(0)


func _load() -> void:
	C.hold(_model, 60, &"raw_a")
	C.grill(_model, 60, 1100, 1200)


func _frames() -> void:
	for i: int in 3:
		await get_tree().process_frame
