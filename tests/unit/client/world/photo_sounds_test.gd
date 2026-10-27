extends GdUnitTestSuite
## The photo task's sounds (#785, photo P6; the photo ADR §1.1 row 7, §4, PD15; the M4 ADR's §3
## item 10): SoundChooser plays ShotTaken's shutter at the camera's lens, PhotoPrinted's print where
## the photo lies on the tray and PhotoHung's at the board (a counted photo the task's success,
## #1341; one without a person the hang), each only within the hearing range of the ears and
## nothing at all from farther away or for a place the model does not know; WorldSounds plays each
## with the range as max_distance, the shutter, the print and the hang on generated placeholder
## blips (no file yet), the success on SfxSet's file.

const RANGE := SoundChooser.HEARING_RANGE_M
const CAMERA := 3
const BOARD := 7
const PHOTO := 20
const LENS_M := 1.6
const CAMERA_AT := Vector3(0, 0, -4)
const BOARD_AT := Vector3(-2, 0, -4)
const TRAY_AT := Vector3(2, 0.9, -4)

var _model: ClientModel


func before_test() -> void:
	_model = ClientModel.new(FixtureBaseMode.mode())
	_station(CAMERA, &"camera", CAMERA_AT)
	_station(BOARD, &"board", BOARD_AT)
	_model.fold(&"ItemSpawned", {"item": PHOTO, "kind": &"photo", "position": TRAY_AT})


func test_the_shutter_plays_at_the_lens_within_the_range() -> void:
	var sound := _choose(&"ShotTaken", _shot(CAMERA), Vector3.ZERO)
	assert_str(String(sound.id)).is_equal(String(SoundChooser.SHUTTER))
	var lens := CAMERA_AT + Vector3.UP * LENS_M
	assert_that(sound.position).is_equal(lens)
	# In the air at the lens: the ray aims at the lens itself.
	assert_that(sound.aim).is_equal(lens)
	# The cut-off is from the lens: just inside and just beyond the range.
	assert_object(_choose(&"ShotTaken", _shot(CAMERA), lens + Vector3(0, 0, RANGE))).is_not_null()
	(
		assert_object(_choose(&"ShotTaken", _shot(CAMERA), lens + Vector3(0, 0, RANGE + 0.01)))
		. is_null()
	)
	# A camera the model never placed makes no sound.
	assert_object(_choose(&"ShotTaken", _shot(42), Vector3.ZERO)).is_null()


func test_the_print_plays_where_the_photo_lies_on_the_tray() -> void:
	var printed := {"item": PHOTO, "shot": 11}
	var sound := _choose(&"PhotoPrinted", printed, Vector3.ZERO)
	assert_str(String(sound.id)).is_equal(String(SoundChooser.PRINT))
	assert_that(sound.position).is_equal(TRAY_AT)
	assert_that(sound.aim).is_equal(TRAY_AT + Vector3.UP * SoundChooser.ITEM_AIM_M)
	(
		assert_object(_choose(&"PhotoPrinted", printed, TRAY_AT + Vector3(RANGE + 0.01, 0, 0)))
		. is_null()
	)
	assert_object(_choose(&"PhotoPrinted", {"item": 77, "shot": 11}, Vector3.ZERO)).is_null()


func test_the_hang_plays_at_the_board_within_the_range() -> void:
	var hung := {"item": PHOTO, "station": BOARD, "counted": true}
	var sound := _choose(&"PhotoHung", hung, Vector3.ZERO)
	# A counted photo is the task's subtask done (#1341): its success, as every task's.
	assert_str(String(sound.id)).is_equal(String(SfxSet.TASK_SUCCESS))
	assert_that(sound.position).is_equal(BOARD_AT)
	assert_that(sound.aim).is_equal(BOARD_AT + Vector3.UP * SoundChooser.HANG_AIM_M)
	assert_float(SoundChooser.HANG_AIM_M).is_greater(0.0)
	# One without a person counts nothing (PD6): the hang, at the same place.
	hung["counted"] = false
	var uncounted := _choose(&"PhotoHung", hung, Vector3.ZERO)
	assert_str(String(uncounted.id)).is_equal(String(SoundChooser.HANG))
	assert_that(uncounted.position).is_equal(BOARD_AT)
	assert_that(uncounted.aim).is_equal(sound.aim)
	assert_object(_choose(&"PhotoHung", hung, BOARD_AT + Vector3(0, 0, RANGE + 0.01))).is_null()
	hung["station"] = 42
	assert_object(_choose(&"PhotoHung", hung, Vector3.ZERO)).is_null()


func test_the_other_photo_events_are_silent() -> void:
	assert_object(_choose(&"FilmLoaded", {"station": CAMERA, "item": 5}, Vector3.ZERO)).is_null()


func test_world_sounds_plays_each_photo_blip_with_the_range_as_max_distance() -> void:
	AudioBuses.ensure()
	var sounds: WorldSounds = auto_free(WorldSounds.new())
	add_child(sounds)
	sounds.model = _model
	sounds.lens_m = LENS_M
	sounds.listener = func() -> Variant: return Vector3.ZERO
	sounds.on_event(&"ShotTaken", _shot(CAMERA))
	sounds.on_event(&"PhotoPrinted", {"item": PHOTO, "shot": 11})
	sounds.on_event(&"PhotoHung", {"item": PHOTO, "station": BOARD, "counted": false})
	assert_int(sounds.played()).is_equal(3)
	var started := sounds.find_children("*", "AudioStreamPlayer3D", false, false)
	assert_int(started.size()).is_equal(3)
	var at: Array[Vector3] = [CAMERA_AT + Vector3.UP * LENS_M, TRAY_AT, BOARD_AT]
	for i: int in 3:
		var played := started[i] as AudioStreamPlayer3D
		assert_float(played.max_distance).is_equal(RANGE)
		assert_that(played.position).is_equal(at[i])
		assert_object(played.stream).is_instanceof(AudioStreamWAV)
	# One blip per id, made once and kept.
	sounds.on_event(&"ShotTaken", _shot(CAMERA))
	var again := sounds.find_children("*", "AudioStreamPlayer3D", false, false)
	assert_object((again[3] as AudioStreamPlayer3D).stream).is_same(
		(started[0] as AudioStreamPlayer3D).stream
	)
	# Beyond the range: nothing starts.
	sounds.listener = func() -> Variant: return CAMERA_AT + Vector3(0, 0, RANGE + 3.0)
	sounds.on_event(&"ShotTaken", _shot(CAMERA))
	assert_int(sounds.played()).is_equal(4)


func test_the_photo_blips_are_short_distinct_placeholders() -> void:
	# PD15: blips built in code until the engineer's files arrive; SfxSet has none for them yet.
	for id: StringName in [SoundChooser.SHUTTER, SoundChooser.PRINT, SoundChooser.HANG]:
		assert_int(SfxSet.paths_for(id).size()).is_equal(0)
		var blip := WorldSounds.photo_blip(id)
		assert_object(blip).is_not_null()
		assert_float(blip.get_length()).is_between(0.05, 1.0)
		assert_float(blip.get_length()).is_equal_approx(WorldSounds.PHOTO_BLIP_SECONDS[id], 0.001)
		assert_int(blip.data.size()).is_greater(1000)
		assert_bool(_peak(blip) > 0.05).is_true()
	# Each id its own sound, not one fallback for all.
	var shutter := WorldSounds.photo_blip(SoundChooser.SHUTTER).data
	var print_blip := WorldSounds.photo_blip(SoundChooser.PRINT).data
	var hang := WorldSounds.photo_blip(SoundChooser.HANG).data
	assert_bool(shutter == print_blip).is_false()
	assert_bool(shutter == hang).is_false()
	assert_bool(print_blip == hang).is_false()
	# The same seed each time: deterministic bytes.
	assert_that(WorldSounds.photo_blip(SoundChooser.PRINT).data).is_equal(
		WorldSounds.photo_blip(SoundChooser.PRINT).data
	)
	assert_object(WorldSounds.photo_blip(SoundChooser.SWING)).is_null()


func _peak(blip: AudioStreamWAV) -> float:
	var peak := 0
	@warning_ignore("integer_division")
	for i: int in blip.data.size() / 2:
		peak = maxi(peak, absi(blip.data.decode_s16(i * 2)))
	return float(peak) / 32767.0


func _choose(event_name: StringName, fields: Dictionary, listener: Vector3) -> SoundChooser.Sound:
	return SoundChooser.choose(
		event_name,
		fields,
		_model,
		func(_peer: int) -> Variant: return null,
		listener,
		RANGE,
		LENS_M
	)


func _shot(station: int) -> Dictionary:
	var record: Array[Dictionary] = []
	return {"station": station, "film": 5, "shot": 11, "record": record}


func _station(id: int, kind: StringName, at: Vector3) -> void:
	_model.fold(
		&"StationPlaced", {"station": id, "kind": kind, "colour": Color.WHITE, "position": at}
	)
