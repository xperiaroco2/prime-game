extends GdUnitTestSuite
## The Generator's clicks (#801, G6; SoundChooser, WorldSounds): SwitchChanged clicks at the
## switch's station and ButtonPressed at the generator's, each aimed SoundChooser.PANEL_AIM_M above
## it, only within the hearing range of the ears and nothing for a station the model never placed;
## WorldSounds plays each on its generated placeholder (no file yet), and the hum's placeholder
## loops.

const G := preload("res://tests/fixtures/client/fixture_generator_client.gd")
const RANGE := SoundChooser.HEARING_RANGE_M

var _model: ClientModel


func before_test() -> void:
	_model = G.dealt()


func test_a_switch_thrown_clicks_at_the_switch_within_the_range() -> void:
	var at: Vector3 = FixtureGeneratorModes.SWITCH_SPOTS[1]
	G.switch_to(_model, 1, false)
	var fields := {"station": G.FIRST_SWITCH + 1, "on": false}
	var sound := _choose(&"SwitchChanged", fields, at)
	assert_str(String(sound.id)).is_equal(String(SoundChooser.SWITCH_CLICK))
	assert_that(sound.position).is_equal(at)
	assert_that(sound.aim).is_equal(at + Vector3.UP * SoundChooser.PANEL_AIM_M)
	assert_object(_choose(&"SwitchChanged", fields, at + Vector3(RANGE, 0, 0))).is_not_null()
	assert_object(_choose(&"SwitchChanged", fields, at + Vector3(RANGE + 0.01, 0, 0))).is_null()
	assert_object(_choose(&"SwitchChanged", {"station": 77, "on": true}, at)).is_null()


func test_the_button_clicks_at_the_generator() -> void:
	var at := FixtureGeneratorModes.GENERATOR_AT
	var sound := _choose(&"ButtonPressed", {"station": G.GENERATOR}, at)
	assert_str(String(sound.id)).is_equal(String(SoundChooser.BUTTON_CLICK))
	assert_that(sound.position).is_equal(at)
	var far := at + Vector3(0, 0, -RANGE - 1)
	assert_object(_choose(&"ButtonPressed", {"station": G.GENERATOR}, far)).is_null()
	assert_object(_choose(&"ButtonPressed", {"station": 77}, at)).is_null()


func test_world_sounds_plays_each_click_on_its_placeholder() -> void:
	var sounds := WorldSounds.new()
	sounds.model = _model
	var ears := FixtureGeneratorModes.GENERATOR_AT
	sounds.listener = func() -> Variant: return ears
	sounds.on_event(&"ButtonPressed", {"station": G.GENERATOR})
	sounds.on_event(&"SwitchChanged", {"station": G.FIRST_SWITCH, "on": true})
	assert_int(sounds.played()).is_equal(2)
	for child: Node in sounds.get_children():
		var player := child as AudioStreamPlayer3D
		assert_object(player.stream).is_instanceof(AudioStreamWAV)
		assert_float(player.max_distance).is_equal(RANGE)
	sounds.free()


func test_the_placeholders_exist_and_only_the_hum_loops() -> void:
	for id: StringName in [SoundChooser.SWITCH_CLICK, SoundChooser.BUTTON_CLICK]:
		var click := WorldSounds.station_blip(id)
		assert_int(click.data.size()).is_greater(0)
		assert_int(click.loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)
	assert_object(WorldSounds.station_blip(SoundChooser.SHUTTER)).is_null()
	var hum := WorldSounds.hum_blip()
	assert_int(hum.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(hum.loop_end).is_equal(hum.data.size() >> 1)


func _choose(event_name: StringName, fields: Dictionary, listener: Vector3) -> SoundChooser.Sound:
	_model.fold(event_name, fields)
	return SoundChooser.choose(
		event_name, fields, _model, func(_peer: int) -> Variant: return null, listener
	)
