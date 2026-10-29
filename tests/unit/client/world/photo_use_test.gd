extends GdUnitTestSuite
## What E offers at the photo task's stations (#786, photo P7; the photo ADR §2), through
## StationUse.usable as the hint and E ask it, from a client's model of FixturePhotoModes.basic():
## the camera holding a film always (the view, the take-out), the empty camera only with a fresh
## film carried, the box always, the printer only with a film with a shot, the board only with a
## photo, none of the last three or the empty camera once the task is done, and never the photo
## spot (a display kind, CE6); with a two-handed item in the hand only the box and the loaded camera
## (its take-out, a take: the photo ADR's §2.4), and no viewfinder there. Plus the frames left
## and the camera's frame as the host's PhotoFrame builds it.

const P := preload("res://tests/fixtures/client/fixture_photo_client.gd")
const FILM := 40
const PHOTO := 50

var _model: ClientModel
var _mode: GameMode


func before_test() -> void:
	_model = P.dealt()
	_mode = FixturePhotoModes.basic()


func test_the_photo_spot_is_never_offered() -> void:
	P.hold(_model, PHOTO, &"photo")
	assert_bool(_usable(P.SPOT)).is_false()


func test_the_box_is_always_offered_also_once_the_task_is_done() -> void:
	assert_bool(_usable(P.BOX)).is_true()
	_done()
	assert_bool(_usable(P.BOX)).is_true()


func test_the_empty_camera_needs_a_fresh_film_carried() -> void:
	assert_bool(_usable(P.CAMERA)).is_false()
	P.hold(_model, FILM, &"film")
	assert_bool(_usable(P.CAMERA)).is_true()


func test_a_fresh_film_on_the_belt_offers_the_load_too() -> void:
	P.hold(_model, FILM, &"film")
	P.fold(_model, SwappedEvent.new(P.OWN, 1))
	assert_bool(_usable(P.CAMERA)).is_true()


func test_an_exposed_film_offers_no_load_but_the_printer() -> void:
	_exposed_film_in_hand()
	assert_bool(_usable(P.CAMERA)).is_false()
	assert_bool(_usable(P.PRINTER)).is_true()


func test_the_printer_needs_a_film_with_a_shot() -> void:
	assert_bool(_usable(P.PRINTER)).is_false()
	P.hold(_model, FILM, &"film")
	assert_bool(_usable(P.PRINTER)).is_false()


func test_the_board_needs_a_photo_carried() -> void:
	assert_bool(_usable(P.BOARD)).is_false()
	P.hold(_model, PHOTO, &"photo")
	assert_bool(_usable(P.BOARD)).is_true()


func test_the_loaded_camera_is_offered_with_empty_hands_and_once_the_task_is_done() -> void:
	P.load_film(_model, FILM)
	assert_bool(_usable(P.CAMERA)).is_true()
	assert_bool(PhotoUse.is_loaded_camera(_model, _mode, P.CAMERA)).is_true()
	_done()
	assert_bool(_usable(P.CAMERA)).is_true()


func test_once_the_task_is_done_the_load_the_printer_and_the_board_are_not_offered() -> void:
	P.hold(_model, FILM, &"film")
	P.hold(_model, PHOTO, &"photo")
	_done()
	assert_bool(_usable(P.CAMERA)).is_false()
	assert_bool(_usable(P.BOARD)).is_false()


func test_a_two_handed_item_in_the_hand_offers_no_camera_printer_or_board() -> void:
	P.hold(_model, FILM, &"film")
	P.fold(_model, SwappedEvent.new(P.OWN, 1))
	P.hold(_model, 41, &"package")
	assert_bool(_usable(P.CAMERA)).is_false()
	# The box's rule has no HandNotTwoHanded: a take is a take (CD3 (b)).
	assert_bool(_usable(P.BOX)).is_true()


func test_a_two_handed_item_in_the_hand_still_offers_the_loaded_camera_s_take_out() -> void:
	P.load_film(_model, FILM)
	P.hold(_model, 41, &"package")
	assert_bool(_usable(P.CAMERA)).is_true()
	# Only the shot is refused (HandNotTwoHanded): the viewfinder asks this.
	assert_bool(StationUse.hand_allows_at(_model, _mode, P.CAMERA)).is_false()
	P.fold(_model, ItemPlacedEvent.new(41, Vector3(0, 0, 3), Items.PUT_DOWN))
	assert_bool(StationUse.hand_allows_at(_model, _mode, P.CAMERA)).is_true()


func test_another_players_film_offers_nothing() -> void:
	P.hold(_model, FILM, &"film", P.OTHER)
	assert_bool(_usable(P.CAMERA)).is_false()


func test_the_frames_left_count_down_with_the_shots() -> void:
	assert_int(PhotoUse.frames_left(_model, _mode, P.CAMERA)).is_equal(0)
	P.load_film(_model, FILM)
	assert_int(PhotoUse.frames_left(_model, _mode, P.CAMERA)).is_equal(FixturePhotoModes.FRAMES)
	P.shoot(_model, FILM)
	assert_int(PhotoUse.frames_left(_model, _mode, P.CAMERA)).is_equal(FixturePhotoModes.FRAMES - 1)
	P.shoot(_model, FILM, 1)
	P.shoot(_model, FILM, 2)
	assert_int(PhotoUse.frames_left(_model, _mode, P.CAMERA)).is_equal(0)


func test_the_frame_is_the_hosts_from_the_lens_at_eye_height_to_the_spot() -> void:
	var frame := PhotoUse.frame_of(_model, _mode, P.CAMERA)
	var eye := _mode.player_rules.eye_height_m
	var host := PhotoFrame.between(
		FixturePhotoModes.CAMERA_AT + Vector3.UP * eye,
		FixturePhotoModes.SPOT_AT + Vector3.UP * eye,
		FixturePhotoModes.FOV_DEG,
		FixturePhotoModes.ASPECT,
		FixturePhotoModes.RANGE_M
	)
	assert_vector(frame.lens).is_equal(host.lens)
	assert_bool(frame.basis.is_equal_approx(host.basis)).is_true()
	assert_float(frame.range_m).is_equal(host.range_m)
	assert_bool(frame.contains(FixturePhotoModes.IN_FRAME + Vector3.UP * eye)).is_true()


func test_no_frame_without_a_photo_spot_or_at_another_station() -> void:
	assert_object(PhotoUse.frame_of(_model, _mode, P.BOX)).is_null()
	_model.stations.erase(P.SPOT)
	assert_object(PhotoUse.frame_of(_model, _mode, P.CAMERA)).is_null()


func _usable(id: int) -> bool:
	return StationUse.usable(_model, _mode, id)


func _done() -> void:
	P.fold(_model, TaskStateEvent.new(P.TASK, &"photo", 2, 2))


func _exposed_film_in_hand() -> void:
	P.load_film(_model, FILM)
	P.shoot(_model, FILM)
	P.fold(_model, ItemPickedUpEvent.new(P.OWN, FILM))
