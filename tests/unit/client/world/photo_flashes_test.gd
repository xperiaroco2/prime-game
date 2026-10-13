extends GdUnitTestSuite
## The photo camera's flash (client/world/photo_flashes.gd; #785, photo P6; the photo ADR §3.3, §4,
## PD15): a ShotTaken lights one OmniLight3D at the camera's lens, shadowed and short-ranged so it
## never lights a room through a wall; it holds until its shot is released (here a test caller
## stands in for P8's render, #787), at least PULSE_S, and the fallback ends it at HOLD_LIMIT_S
## when no render ever calls (a headless client).

const CAMERA := 3
const BOARD := 7
const CAMERA_AT := Vector3(2, 0, -5)
const LENS_M := 1.6

var _model: ClientModel
var _flashes: PhotoFlashes


func before_test() -> void:
	_model = ClientModel.new(FixtureBaseMode.mode())
	_station(CAMERA, &"camera", CAMERA_AT)
	_station(BOARD, &"board", Vector3(-2, 0, -5))
	_flashes = auto_free(PhotoFlashes.new())
	add_child(_flashes)
	_flashes.model = _model
	_flashes.lens_m = LENS_M


func test_a_shot_lights_a_shadowed_short_flash_at_the_lens() -> void:
	_shot(CAMERA, 11)
	assert_int(_flashes.lit()).is_equal(1)
	var light := _flashes.light_of(11)
	assert_object(light).is_not_null()
	assert_object(light.get_parent()).is_same(_flashes)
	assert_that(light.position).is_equal(CAMERA_AT + Vector3.UP * LENS_M)
	# Shadows on, or the light passes through walls and lights a room no eye of it sees.
	assert_bool(light.shadow_enabled).is_true()
	assert_float(light.omni_range).is_equal(PhotoFlashes.RANGE_M)
	# Short: well under the hearing range, about a room around the lens.
	assert_float(light.omni_range).is_less_equal(SoundChooser.HEARING_RANGE_M / 2.0)
	assert_float(light.light_energy).is_greater(0.0)
	assert_bool(light.visible).is_true()
	# Nothing else drawn: no mesh, sprite or marker that could show through the level.
	assert_int(_flashes.get_child_count()).is_equal(1)
	assert_int(light.get_child_count()).is_equal(0)


func test_the_flash_holds_until_its_shot_is_released() -> void:
	_shot(CAMERA, 11)
	var light := _flashes.light_of(11)
	# Unreleased, it stays on past the shortest pulse, as a queued render waits its frame.
	_flashes.advance(PhotoFlashes.PULSE_S * 3.0)
	assert_object(_flashes.light_of(11)).is_same(light)
	assert_bool(light.visible).is_true()
	# The test caller: the render of shot 11 has drawn.
	_flashes.release(11)
	assert_object(_flashes.light_of(11)).is_null()
	assert_int(_flashes.lit()).is_equal(0)
	assert_bool(light.visible).is_false()
	assert_bool(light.is_queued_for_deletion()).is_true()


func test_a_release_in_the_next_frame_still_shows_the_shortest_pulse() -> void:
	_shot(CAMERA, 11)
	_flashes.advance(0.016)
	_flashes.release(11)
	assert_object(_flashes.light_of(11)).is_not_null()
	_flashes.advance(PhotoFlashes.PULSE_S)
	assert_object(_flashes.light_of(11)).is_null()


func test_the_fallback_ends_a_flash_no_render_releases() -> void:
	_shot(CAMERA, 11)
	var light := _flashes.light_of(11)
	_flashes.advance(PhotoFlashes.HOLD_LIMIT_S - 0.05)
	assert_int(_flashes.lit()).is_equal(1)
	_flashes.advance(0.05)
	assert_int(_flashes.lit()).is_equal(0)
	assert_bool(light.visible).is_false()
	# A late release of an ended shot does nothing.
	_flashes.release(11)
	assert_int(_flashes.lit()).is_equal(0)


func test_the_fallback_runs_on_the_frames_of_the_tree() -> void:
	# _process ages the flashes: a headless client's flash ends without any caller.
	_shot(CAMERA, 11)
	var light := _flashes.light_of(11)
	var waited := 0
	while _flashes.lit() > 0 and waited < 600:
		await get_tree().process_frame
		waited += 1
	assert_int(_flashes.lit()).is_equal(0)
	# Its light left the tree (freed at the end of the frame).
	assert_bool(is_instance_valid(light) and light.is_inside_tree()).is_false()


func test_each_shot_holds_its_own_flash() -> void:
	_shot(CAMERA, 11)
	_flashes.advance(PhotoFlashes.PULSE_S)
	_shot(CAMERA, 12)
	assert_int(_flashes.lit()).is_equal(2)
	_flashes.release(11)
	assert_object(_flashes.light_of(11)).is_null()
	assert_object(_flashes.light_of(12)).is_not_null()
	# A release of a shot never taken changes nothing.
	_flashes.release(99)
	assert_int(_flashes.lit()).is_equal(1)


func test_a_recycled_shot_id_ends_the_older_flash() -> void:
	_shot(CAMERA, 11)
	var older := _flashes.light_of(11)
	_shot(CAMERA, 11)
	var newer := _flashes.light_of(11)
	assert_object(newer).is_not_same(older)
	assert_bool(older.visible).is_false()
	assert_int(_flashes.lit()).is_equal(1)
	assert_int(_flashes.started()).is_equal(2)


func test_no_flash_without_a_known_camera_a_model_or_for_other_events() -> void:
	_shot(42, 11)
	assert_int(_flashes.started()).is_equal(0)
	_flashes.on_event(&"PhotoPrinted", {"item": 5, "shot": 11})
	_flashes.on_event(&"PhotoHung", {"item": 5, "station": BOARD, "counted": true})
	_flashes.on_event(&"FilmLoaded", {"station": CAMERA, "item": 5})
	assert_int(_flashes.started()).is_equal(0)
	_flashes.model = null
	_shot(CAMERA, 11)
	assert_int(_flashes.started()).is_equal(0)


func test_clear_ends_every_flash() -> void:
	_shot(CAMERA, 11)
	_shot(CAMERA, 12)
	_flashes.clear()
	assert_int(_flashes.lit()).is_equal(0)


func _shot(station: int, shot: int) -> void:
	var record: Array[Dictionary] = []
	_flashes.on_event(&"ShotTaken", {"station": station, "film": 5, "shot": shot, "record": record})


func _station(id: int, kind: StringName, at: Vector3) -> void:
	_model.fold(
		&"StationPlaced", {"station": id, "kind": kind, "colour": Color.WHITE, "position": at}
	)
