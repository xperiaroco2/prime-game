extends GdUnitTestSuite
## Cooking's sounds (#776, the cooking ADR's CD14 (a), amended by #1101; SoundChooser, WorldSounds):
## IngredientPlaced clicks at its place whatever it is (nothing is right or wrong before a serve),
## BurgerPlated chimes there, BurgerServed plays the task's success when right and its error when
## wrong (#1341), at the order board; GrillLoaded clicks at the grill; ItemChanged dings for a fried
## patty and plays the task's error for the burnt one where it lies, told by the client's own copy
## of the mode (none: silent); each only within the hearing range, aimed SoundChooser.COUNTER_AIM_M
## above its station; WorldSounds plays Cooking's own sounds on generated placeholders, the task's
## on SfxSet's files, and the sizzle's loops.

const C := preload("res://tests/fixtures/client/fixture_cooking_client.gd")
const RANGE := SoundChooser.HEARING_RANGE_M
const PLACE_AT := FixtureCookingModes.PLACE_SPOTS[0]

var _mode: GameMode
var _model: ClientModel


func before_test() -> void:
	_mode = FixtureCookingModes.basic(2)
	_model = C.dealt(2, _mode)


func test_any_ingredient_clicks_the_same_at_the_place() -> void:
	# Before #1101 a right one chimed and a wrong one buzzed: no sound tells them apart now.
	C.hold(_model, 50, &"bun_a")
	var sound := _choose(&"IngredientPlaced", _put(50), PLACE_AT)
	assert_str(String(sound.id)).is_equal(String(SoundChooser.PUT_DOWN))
	assert_that(sound.position).is_equal(PLACE_AT)
	assert_that(sound.aim).is_equal(PLACE_AT + Vector3.UP * SoundChooser.COUNTER_AIM_M)
	C.hold(_model, 51, &"fried_b")
	assert_str(String(_choose(&"IngredientPlaced", _put(51), PLACE_AT).id)).is_equal(
		String(SoundChooser.PUT_DOWN)
	)


func test_a_plated_burger_chimes_at_its_place() -> void:
	C.hold(_model, 52, &"burger")
	var fields := {"item": 52, "station": C.FIRST_PLACE, "bun": &"bun_a"}
	fields.merge({"patty": &"fried_a", "herb": &"herb_a"})
	var sound := _choose(&"BurgerPlated", fields, PLACE_AT)
	assert_str(String(sound.id)).is_equal(String(SoundChooser.CHIME))
	assert_that(sound.position).is_equal(PLACE_AT)


func test_a_right_serve_plays_the_success_and_a_wrong_one_the_error_at_the_order_board() -> void:
	var at := FixtureCookingModes.ORDER_BOARD_AT
	var wrong := _choose(&"BurgerServed", {"station": C.FIRST_PLACE, "right": false}, at)
	assert_str(String(wrong.id)).is_equal(String(SfxSet.TASK_ERROR))
	assert_that(wrong.position).is_equal(at)
	var right := _choose(&"BurgerServed", {"station": C.FIRST_PLACE, "right": true}, at)
	assert_str(String(right.id)).is_equal(String(SfxSet.TASK_SUCCESS))
	assert_that(right.position).is_equal(at)


func test_a_serve_is_silent_without_the_mode_or_for_an_unknown_place() -> void:
	var at := FixtureCookingModes.ORDER_BOARD_AT
	var fields := {"station": C.FIRST_PLACE, "right": true}
	assert_object(SoundChooser.choose(&"BurgerServed", fields, _model, _nobody, at)).is_null()
	assert_object(_choose(&"BurgerServed", {"station": 99, "right": true}, at)).is_null()


func test_a_put_beyond_the_range_or_at_an_unknown_station_is_silent() -> void:
	C.hold(_model, 50, &"bun_a")
	var far := PLACE_AT + Vector3(RANGE + 0.01, 0, 0)
	assert_object(_choose(&"IngredientPlaced", _put(50), far)).is_null()
	C.hold(_model, 51, &"bun_a")
	var unknown := {"item": 51, "station": 99}
	assert_object(_choose(&"IngredientPlaced", unknown, PLACE_AT)).is_null()


func test_the_grill_clicks_then_dings_when_fried_and_plays_the_error_when_burnt() -> void:
	var at := FixtureCookingModes.GRILL_AT
	C.hold(_model, 60, &"raw_a")
	var fields := {"station": C.GRILL, "item": 60, "fried": 1100, "burnt": 1200}
	var put := _choose(&"GrillLoaded", fields, at)
	assert_str(String(put.id)).is_equal(String(SoundChooser.PUT_DOWN))
	assert_that(put.position).is_equal(at)
	var fried := _choose(&"ItemChanged", {"item": 60, "kind": &"fried_a"}, at)
	assert_str(String(fried.id)).is_equal(String(SoundChooser.DING))
	assert_that(fried.position).is_equal(at)
	var burnt := _choose(&"ItemChanged", {"item": 60, "kind": &"burnt"}, at)
	assert_str(String(burnt.id)).is_equal(String(SfxSet.TASK_ERROR))
	assert_that(burnt.position).is_equal(at)
	(
		assert_object(
			_choose(&"ItemChanged", {"item": 60, "kind": &"burnt"}, at + Vector3(0, 0, -RANGE - 1))
		)
		. is_null()
	)


func test_an_item_change_is_silent_without_the_mode_or_for_another_kind() -> void:
	var at := FixtureCookingModes.GRILL_AT
	C.hold(_model, 60, &"raw_a")
	_model.fold(&"GrillLoaded", {"station": C.GRILL, "item": 60, "fried": 1100, "burnt": 1200})
	var fields := {"item": 60, "kind": &"fried_a"}
	_model.fold(&"ItemChanged", fields)
	var none := SoundChooser.choose(&"ItemChanged", fields, _model, _nobody, at)
	assert_object(none).is_null()
	assert_object(_choose(&"ItemChanged", {"item": 60, "kind": &"bun_a"}, at)).is_null()


func test_world_sounds_plays_the_ding_on_its_placeholder_and_the_burnt_on_the_error() -> void:
	var sounds := WorldSounds.new()
	sounds.model = _model
	sounds.mode = _mode
	var ears := FixtureCookingModes.GRILL_AT
	sounds.listener = func() -> Variant: return ears
	C.hold(_model, 60, &"raw_a")
	var fields := {"station": C.GRILL, "item": 60, "fried": 1100, "burnt": 1200}
	_model.fold(&"GrillLoaded", fields)
	_model.fold(&"ItemChanged", {"item": 60, "kind": &"fried_a"})
	sounds.on_event(&"ItemChanged", {"item": 60, "kind": &"fried_a"})
	_model.fold(&"ItemChanged", {"item": 60, "kind": &"burnt"})
	sounds.on_event(&"ItemChanged", {"item": 60, "kind": &"burnt"})
	assert_int(sounds.played()).is_equal(2)
	var started := sounds.get_children()
	assert_object((started[0] as AudioStreamPlayer3D).stream).is_instanceof(AudioStreamWAV)
	assert_object((started[1] as AudioStreamPlayer3D).stream).is_same(
		sounds.sfx.stream_for(SfxSet.TASK_ERROR)
	)
	for child: Node in started:
		assert_float((child as AudioStreamPlayer3D).max_distance).is_equal(RANGE)
	sounds.free()


func test_the_placeholders_exist_and_only_the_sizzle_loops() -> void:
	for id: StringName in WorldSounds.COOKING_BLIP_SECONDS:
		var blip := WorldSounds.cooking_blip(id)
		assert_int(blip.data.size()).is_greater(0)
		assert_int(blip.loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)
	assert_object(WorldSounds.cooking_blip(SoundChooser.SHUTTER)).is_null()
	var sizzle := WorldSounds.sizzle_blip()
	assert_int(sizzle.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(sizzle.loop_end).is_equal(sizzle.data.size() >> 1)


func _put(item: int) -> Dictionary:
	return {"item": item, "station": C.FIRST_PLACE}


func _nobody(_peer: int) -> Variant:
	return null


func _choose(event_name: StringName, fields: Dictionary, listener: Vector3) -> SoundChooser.Sound:
	_model.fold(event_name, fields)
	return SoundChooser.choose(event_name, fields, _model, _nobody, listener, RANGE, 0.0, _mode)
