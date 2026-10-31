extends GdUnitTestSuite
## The photo booth as the players see it (client/world/booth_views.gd; #1397, ARCHITECTURE §4.7.62):
## the lamp above the booth while a session runs (shadowed, short, as PhotoFlashes'), the
## countdown's beeps on the host's ticks (3, 2, 1 before the first flash, the gap's before each
## next), ended by a flash, a print or a stop; the white on the screen only for the own player
## in the FLASH record; the print prop sliding out of the slot and gone; nothing under it that
## renders a view (no Camera3D, SubViewport or ViewportTexture), so nothing draws the booth's
## inside before a strip exists. SoundChooser plays the beep and the flash's shutter at the lamp,
## the print at the slot.

const BOOTH := 4
const BOOTH_AT := Vector3(3, 0, -6)
const OWN := 1
const OTHER := 2
const RATE := Ticks.RATE

var _model: ClientModel
var _book: BoothBook
var _views: BoothViews
var _tick := 100
var _sounds: Array[Dictionary] = []


func before_test() -> void:
	_model = ClientModel.new(FixtureBaseMode.mode())
	_model.own_peer = OWN
	_model.fold(
		&"StationPlaced",
		{"station": BOOTH, "kind": &"booth", "colour": Color.WHITE, "position": BOOTH_AT}
	)
	_book = BoothBook.new()
	_views = auto_free(BoothViews.new())
	add_child(_views)
	_views.set_process(false)
	_views.model = _model
	_views.book = _book
	_views.host_tick = func() -> int: return _tick
	_sounds.clear()
	_views.sound_due.connect(
		func(event_name: StringName, fields: Dictionary) -> void:
			_sounds.append({"event": event_name, "station": fields["station"]})
	)


func test_a_start_lights_the_lamp_above_the_booth_shadowed_and_short() -> void:
	_step(BoothStepEvent.STARTED, {"frames": 3, "countdown": 3 * RATE, "gap": 2 * RATE})
	var light := _views.lamp_of(BOOTH)
	assert_object(light).is_not_null()
	assert_that(light.global_position).is_equal(BOOTH_AT + Vector3.UP * BoothViews.LAMP_LIFT_M)
	assert_bool(light.shadow_enabled).is_true()
	assert_float(light.omni_range).is_less_equal(SoundChooser.HEARING_RANGE_M / 2.0)
	assert_float(light.light_energy).is_equal_approx(BoothViews.LAMP_ENERGY, 0.001)
	assert_int(_book.running_at(BOOTH).started_at).is_equal(100)


func test_the_countdown_beeps_on_the_host_ticks_once_each() -> void:
	_step(BoothStepEvent.STARTED, {"frames": 3, "countdown": 3 * RATE, "gap": 2 * RATE})
	assert_array(Array(_views.beeps_due(BOOTH))).contains_exactly([100, 100 + RATE, 100 + 2 * RATE])
	_views.tick_to(100)
	assert_int(_sounds.size()).is_equal(1)
	assert_that(_sounds[0]).is_equal({"event": BoothViews.BEEP_EVENT, "station": BOOTH})
	assert_float(_views.lamp_of(BOOTH).light_energy).is_equal_approx(BoothViews.BEEP_ENERGY, 0.001)
	_views.tick_to(100)
	assert_int(_sounds.size()).is_equal(1)
	_views.tick_to(100 + 2 * RATE)
	assert_int(_sounds.size()).is_equal(3)
	assert_array(Array(_views.beeps_due(BOOTH))).is_empty()


func test_no_beep_without_the_host_s_word() -> void:
	# A local clock alone plays nothing: the beeps wait for the host tick.
	_step(BoothStepEvent.STARTED, {"frames": 3, "countdown": 3 * RATE, "gap": 2 * RATE})
	_views.advance(10.0)
	assert_int(_sounds.size()).is_equal(0)


func test_a_flash_ends_the_beeps_due_flares_and_plans_the_gap_s() -> void:
	_step(BoothStepEvent.STARTED, {"frames": 2, "countdown": 3 * RATE, "gap": 2 * RATE})
	_tick = 150
	_step(BoothStepEvent.FLASH, {"frame": 0, "record": [_row(OTHER)]})
	assert_float(_views.lamp_of(BOOTH).light_energy).is_equal_approx(BoothViews.FLASH_ENERGY, 0.001)
	assert_array(Array(_views.beeps_due(BOOTH))).contains_exactly([150, 150 + RATE])
	_views.advance(BoothViews.FLASH_SECONDS)
	assert_float(_views.lamp_of(BOOTH).light_energy).is_equal_approx(BoothViews.LAMP_ENERGY, 0.001)
	# The last frame: no beeps after it.
	_step(BoothStepEvent.FLASH, {"frame": 1, "record": [_row(OTHER)]})
	assert_array(Array(_views.beeps_due(BOOTH))).is_empty()


func test_the_white_shows_only_for_the_own_player_in_the_frame() -> void:
	_step(BoothStepEvent.STARTED, {"frames": 2, "countdown": 3 * RATE, "gap": 2 * RATE})
	_step(BoothStepEvent.FLASH, {"frame": 0, "record": [_row(OTHER)]})
	assert_float(_views.overlay_alpha()).is_equal(0.0)
	assert_bool(_views.overlay.visible).is_false()
	_step(BoothStepEvent.FLASH, {"frame": 1, "record": [_row(OTHER), _row(OWN)]})
	assert_float(_views.overlay_alpha()).is_equal_approx(BoothViews.OVERLAY_ALPHA, 0.001)
	_views.advance(BoothViews.FLASH_SECONDS / 2.0)
	assert_float(_views.overlay_alpha()).is_equal_approx(BoothViews.OVERLAY_ALPHA / 2.0, 0.001)
	_views.advance(BoothViews.FLASH_SECONDS)
	assert_bool(_views.overlay.visible).is_false()
	# Mild: never a full white.
	assert_float(BoothViews.OVERLAY_ALPHA).is_less(1.0)


func test_a_print_slides_a_prop_out_of_the_slot_and_the_lamp_goes() -> void:
	_step(BoothStepEvent.STARTED, {"frames": 1, "countdown": 3 * RATE, "gap": 2 * RATE})
	_step(BoothStepEvent.FLASH, {"frame": 0, "record": [_row(OWN)]})
	_step(BoothStepEvent.PRINTED, {"items": PackedInt32Array([30])})
	var props := _views.prints()
	assert_int(props.size()).is_equal(1)
	var slot := BOOTH_AT + Vector3.UP * BoothViews.SLOT_LIFT_M
	assert_that(props[0].position).is_equal(slot)
	_views.advance(BoothViews.PRINT_SECONDS / 2.0)
	assert_float(props[0].position.y).is_less(slot.y)
	assert_float(props[0].position.y).is_greater(slot.y - BoothViews.PRINT_DROP_M)
	_views.advance(BoothViews.PRINT_SECONDS)
	assert_array(_views.prints()).is_empty()
	assert_object(_views.lamp_of(BOOTH)).is_null()


func test_a_stop_ends_the_beeps_and_the_lamp_with_no_print() -> void:
	_step(BoothStepEvent.STARTED, {"frames": 3, "countdown": 3 * RATE, "gap": 2 * RATE})
	_step(BoothStepEvent.STOPPED, {})
	assert_array(Array(_views.beeps_due(BOOTH))).is_empty()
	_views.advance(BoothViews.FLASH_SECONDS)
	assert_object(_views.lamp_of(BOOTH)).is_null()
	assert_array(_views.prints()).is_empty()


func test_nothing_under_it_renders_a_view_of_the_booth() -> void:
	_step(BoothStepEvent.STARTED, {"frames": 1, "countdown": 3 * RATE, "gap": 2 * RATE})
	_step(BoothStepEvent.FLASH, {"frame": 0, "record": [_row(OWN)]})
	_step(BoothStepEvent.PRINTED, {"items": PackedInt32Array([30])})
	for node: Node in _views.find_children("*", "", true, false):
		assert_bool(node is Camera3D or node is Viewport).is_false()
	# The source names none of them outside its comments.
	var source := FileAccess.get_file_as_string("res://client/world/booth_views.gd")
	for line: String in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		for name: String in ["Camera3D", "SubViewport", "ViewportTexture", "get_texture"]:
			assert_bool(line.contains(name)).override_failure_message(line).is_false()


func test_the_booth_s_sounds_play_at_the_lamp_and_the_slot() -> void:
	var lamp := BOOTH_AT + Vector3.UP * BoothViews.LAMP_LIFT_M
	var beep := _choose(BoothViews.BEEP_EVENT, {"station": BOOTH}, lamp)
	assert_str(String(beep.id)).is_equal(String(SoundChooser.BOOTH_BEEP))
	assert_that(beep.position).is_equal(lamp)
	var flash := {"station": BOOTH, "step": BoothStepEvent.FLASH}
	var shutter := _choose(BoothBook.STEP_EVENT, flash, lamp)
	assert_str(String(shutter.id)).is_equal(String(SoundChooser.SHUTTER))
	var printed := {"station": BOOTH, "step": BoothStepEvent.PRINTED, "items": [30, 31, 32]}
	var print_sound := _choose(BoothBook.STEP_EVENT, printed, lamp)
	assert_str(String(print_sound.id)).is_equal(String(SoundChooser.PRINT))
	assert_that(print_sound.position).is_equal(BOOTH_AT + Vector3.UP * BoothViews.SLOT_LIFT_M)
	# The start and a stop are silent; beyond the range and at an unknown booth, nothing.
	var started := {"station": BOOTH, "step": BoothStepEvent.STARTED}
	assert_object(_choose(BoothBook.STEP_EVENT, started, lamp)).is_null()
	var far := lamp + Vector3(0, 0, SoundChooser.HEARING_RANGE_M + 0.01)
	assert_object(_choose(BoothViews.BEEP_EVENT, {"station": BOOTH}, far)).is_null()
	assert_object(_choose(BoothViews.BEEP_EVENT, {"station": 42}, lamp)).is_null()


func test_the_beep_is_a_short_placeholder_of_its_own() -> void:
	assert_int(SfxSet.paths_for(SoundChooser.BOOTH_BEEP).size()).is_equal(0)
	var blip := WorldSounds.photo_blip(SoundChooser.BOOTH_BEEP)
	assert_object(blip).is_not_null()
	assert_float(blip.get_length()).is_between(0.05, 0.5)
	assert_bool(blip.data == WorldSounds.photo_blip(SoundChooser.SHUTTER).data).is_false()


func _step(step: int, extra: Dictionary) -> void:
	var fields := {"station": BOOTH, "strip": 1, "step": step}
	fields.merge(extra)
	_book.fold(BoothBook.STEP_EVENT, fields)
	_views.on_event(BoothBook.STEP_EVENT, fields)


func _row(peer: int) -> Dictionary:
	return {"peer": peer, "colour": 0, "position": BOOTH_AT, "facing": Vector3.FORWARD}


func _choose(event_name: StringName, fields: Dictionary, listener: Vector3) -> SoundChooser.Sound:
	return SoundChooser.choose(
		event_name, fields, _model, func(_peer: int) -> Variant: return null, listener
	)
