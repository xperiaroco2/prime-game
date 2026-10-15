extends GdUnitTestSuite
## TargetChoice over the photo task (client/world/target_choice.gd; #786, the photo ADR §9 P7),
## pure: the film loaded in the camera is never an item target (it lies on the camera, where
## aim_at names no point for it), the camera is named instead, and the photo spot (a display kind)
## is never a station target, whatever the hand holds. FixturePhotoClient's stations at
## FixturePhotoModes' markers: the camera at (0, 0, 20), the photo spot at (0, 0, 30).

const C := preload("res://tests/fixtures/client/fixture_photo_client.gd")
const FILM := 60
const NO_DEVICE := -1

var _model: ClientModel
var _mode: GameMode


func before_test() -> void:
	_mode = FixturePhotoModes.basic()
	_model = C.dealt()


func test_the_loaded_film_is_never_an_item_target() -> void:
	C.load_film(_model, FILM)
	var feet := FixturePhotoModes.CAMERA_AT + Vector3(0, 0, 0.5)
	var eye := feet + Vector3.UP * 1.6
	var film := _model.items[FILM]
	assert_int(film.on_station).is_equal(C.CAMERA)
	assert_object(TargetChoice.aim_at(_model, FILM)).is_null()
	# Straight at where it lies, and at its look's middle there: no item.
	for at: Vector3 in [film.position, ItemView.centre_of(film.kind, film.position)]:
		var look := (at - eye).normalized()
		var picked := TargetChoice.choose(
			_model, eye, look, TargetChoice.RAY_M, feet, TargetChoice.hint_reach_of(_mode)
		)
		assert_int(picked).is_equal(-1)


func test_the_camera_holding_the_film_is_named_instead() -> void:
	C.load_film(_model, FILM)
	var target := _aimed_at(C.CAMERA, FixturePhotoModes.CAMERA_AT + Vector3(0, 0, 0.5))
	assert_bool(target.is_station()).is_true()
	assert_int(target.id).is_equal(C.CAMERA)


func test_the_photo_spot_is_never_a_station_target() -> void:
	var feet := FixturePhotoModes.SPOT_AT + Vector3(0, 0, -0.5)
	assert_int(_aimed_at(C.SPOT, feet).kind).is_equal(TargetChoice.Target.Kind.NONE)
	C.hold(_model, FILM, &"film")
	assert_int(_aimed_at(C.SPOT, feet).kind).is_equal(TargetChoice.Target.Kind.NONE)
	C.fold(_model, ItemPlacedEvent.new(FILM, Vector3(5, 0, 5), Items.PUT_DOWN))
	C.hold(_model, FILM + 1, &"photo")
	assert_int(_aimed_at(C.SPOT, feet).kind).is_equal(TargetChoice.Target.Kind.NONE)


## What the crosshair names from `feet` (eye 1.6 m up) looking at station `id`'s aim point.
func _aimed_at(id: int, feet: Vector3) -> TargetChoice.Target:
	var eye := feet + Vector3.UP * 1.6
	var look := (TargetChoice.aim_point(_model.stations[id]) - eye).normalized()
	return TargetChoice.choose_target(
		_model,
		_mode,
		eye,
		look,
		TargetChoice.RAY_M,
		feet,
		TargetChoice.hint_reach_of(_mode),
		NO_DEVICE
	)
