extends GdUnitTestSuite
## Cooking's sounds (#776, the cooking ADR's CD14 (a); SoundChooser, WorldSounds): IngredientPlaced
## chimes for a right ingredient, buzzes for a wrong one and plays the burger's done sound for the
## third right one, at its place; GrillLoaded clicks at the grill; ItemChanged dings for a fried
## patty and hisses for the burnt one where it lies, told by the client's own copy of the mode
## (none: silent); each only within the hearing range, aimed SoundChooser.COUNTER_AIM_M above its
## station; WorldSounds plays each on a generated placeholder and the sizzle's loops.

const C := preload("res://tests/fixtures/client/fixture_cooking_client.gd")
const RANGE := SoundChooser.HEARING_RANGE_M
const PLACE_AT := FixtureCookingModes.PLACE_SPOTS[0]

var _mode: GameMode
var _model: ClientModel


func before_test() -> void:
	_mode = FixtureCookingModes.basic(2)
	_model = C.dealt(2, _mode)


func test_a_right_ingredient_chimes_and_a_wrong_one_buzzes_at_the_place() -> void:
	C.hold(_model, 50, &"bun_a")
	var sound := _choose(&"IngredientPlaced", _put(50, true), PLACE_AT)
	assert_str(String(sound.id)).is_equal(String(SoundChooser.CHIME))
	assert_that(sound.position).is_equal(PLACE_AT)
	assert_that(sound.aim).is_equal(PLACE_AT + Vector3.UP * SoundChooser.COUNTER_AIM_M)
	C.hold(_model, 51, &"bun_b")
	assert_str(String(_choose(&"IngredientPlaced", _put(51, false), PLACE_AT).id)).is_equal(
		String(SoundChooser.BUZZ)
	)


func test_the_third_right_ingredient_plays_the_burger_done() -> void:
	for i: int in 2:
		C.hold(_model, 50 + i, &"bun_a")
		C.put(_model, 50 + i, 0, true)
	C.hold(_model, 52, &"herb_a")
	var sound := _choose(&"IngredientPlaced", _put(52, true), PLACE_AT)
	assert_str(String(sound.id)).is_equal(String(SoundChooser.BURGER_DONE))


func test_a_put_beyond_the_range_or_at_an_unknown_station_is_silent() -> void:
	C.hold(_model, 50, &"bun_a")
	var far := PLACE_AT + Vector3(RANGE + 0.01, 0, 0)
	assert_object(_choose(&"IngredientPlaced", _put(50, true), far)).is_null()
	C.hold(_model, 51, &"bun_a")
	var unknown := {"item": 51, "station": 99, "right": true}
	assert_object(_choose(&"IngredientPlaced", unknown, PLACE_AT)).is_null()


func test_the_grill_clicks_then_dings_when_fried_and_hisses_when_burnt() -> void:
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
	assert_str(String(burnt.id)).is_equal(String(SoundChooser.HISS))
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


func test_world_sounds_plays_each_cooking_sound_on_its_placeholder() -> void:
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
	for child: Node in sounds.get_children():
		var player := child as AudioStreamPlayer3D
		assert_object(player.stream).is_instanceof(AudioStreamWAV)
		assert_float(player.max_distance).is_equal(RANGE)
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


func _put(item: int, right: bool) -> Dictionary:
	return {"item": item, "station": C.FIRST_PLACE, "right": right}


func _nobody(_peer: int) -> Variant:
	return null


func _choose(event_name: StringName, fields: Dictionary, listener: Vector3) -> SoundChooser.Sound:
	_model.fold(event_name, fields)
	return SoundChooser.choose(event_name, fields, _model, _nobody, listener, RANGE, 0.0, _mode)
