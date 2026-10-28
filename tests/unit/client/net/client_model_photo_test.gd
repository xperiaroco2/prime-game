extends GdUnitTestSuite
## ClientModel's folds of the photo camera (#786, photo P7; the photo ADR §2.2 to §2.4, §4):
## FilmLoaded takes the film out of the loader's hand or belt (the host sends no ItemPlaced for
## the load) and lays it at the camera, the camera keeping the film and its shot count from
## ShotTaken (its film and count only); the film's ItemPickedUp, ItemPlaced or ItemVanished empties
## the camera. A film keeps its shots wherever it goes, until it vanishes. Nothing kept names who
## loaded or shot.

const P := preload("res://tests/fixtures/client/fixture_photo_client.gd")
const FILM := 40

var _model: ClientModel


func before_test() -> void:
	_model = P.dealt()


func test_a_load_takes_the_film_out_of_the_hand_and_lays_it_at_the_camera() -> void:
	P.load_film(_model, FILM)
	var film := _model.items[FILM]
	assert_int(_model.hand_item(P.OWN)).is_equal(-1)
	assert_int(film.holder).is_equal(ClientModel.NO_HOLDER)
	assert_bool(film.rests()).is_true()
	assert_int(film.on_station).is_equal(P.CAMERA)
	assert_bool(film.locked).is_false()
	assert_vector(film.position).is_equal(FixturePhotoModes.CAMERA_AT)
	var camera := _model.stations[P.CAMERA]
	assert_int(camera.film).is_equal(FILM)
	assert_int(camera.shots).is_equal(0)


func test_a_film_on_the_belt_leaves_the_belt_at_the_load() -> void:
	P.hold(_model, FILM, &"film")
	P.fold(_model, SwappedEvent.new(P.OWN, 1))
	assert_int(_model.belt_item(P.OWN)).is_equal(FILM)
	P.fold(_model, FilmLoadedEvent.new(P.CAMERA, FILM))
	assert_int(_model.belt_item(P.OWN)).is_equal(-1)
	assert_bool(_model.items[FILM].belted).is_false()


func test_each_shot_counts_on_the_camera_and_its_film() -> void:
	P.load_film(_model, FILM)
	P.shoot(_model, FILM, 0)
	P.shoot(_model, FILM, 1)
	assert_int(_model.stations[P.CAMERA].shots).is_equal(2)
	assert_int(_model.film_shots[FILM]).is_equal(2)


func test_the_film_picked_up_empties_the_camera_and_keeps_its_shots() -> void:
	P.load_film(_model, FILM)
	P.shoot(_model, FILM)
	P.fold(_model, ItemPickedUpEvent.new(P.OTHER, FILM))
	var camera := _model.stations[P.CAMERA]
	assert_int(camera.film).is_equal(-1)
	assert_int(camera.shots).is_equal(0)
	assert_int(_model.items[FILM].on_station).is_equal(-1)
	assert_int(_model.items[FILM].holder).is_equal(P.OTHER)
	assert_int(_model.film_shots[FILM]).is_equal(1)


func test_the_film_taken_onto_the_belt_beside_a_two_handed_item_empties_the_camera() -> void:
	P.load_film(_model, FILM)
	P.hold(_model, 41, &"package")
	P.fold(_model, ItemPickedUpEvent.new(P.OWN, FILM, FILM))
	assert_int(_model.stations[P.CAMERA].film).is_equal(-1)
	assert_int(_model.belt_item(P.OWN)).is_equal(FILM)


func test_the_film_vanishing_empties_the_camera_and_forgets_its_shots() -> void:
	P.load_film(_model, FILM)
	P.shoot(_model, FILM)
	P.fold(_model, ItemVanishedEvent.new(FILM))
	assert_int(_model.stations[P.CAMERA].film).is_equal(-1)
	assert_int(_model.stations[P.CAMERA].shots).is_equal(0)
	assert_bool(_model.film_shots.has(FILM)).is_false()


func test_a_film_put_down_elsewhere_empties_the_camera() -> void:
	P.load_film(_model, FILM)
	P.fold(_model, ItemPlacedEvent.new(FILM, Vector3(1, 0, 1), Items.PUT_DOWN))
	assert_int(_model.stations[P.CAMERA].film).is_equal(-1)


func test_another_item_moving_leaves_the_camera_loaded() -> void:
	P.load_film(_model, FILM)
	P.hold(_model, 42, &"film")
	P.fold(_model, ItemVanishedEvent.new(42))
	assert_int(_model.stations[P.CAMERA].film).is_equal(FILM)


func test_a_load_at_an_unknown_station_still_lays_the_film_down() -> void:
	P.hold(_model, FILM, &"film")
	P.fold(_model, FilmLoadedEvent.new(99, FILM))
	assert_int(_model.hand_item(P.OWN)).is_equal(-1)
	assert_bool(_model.stations.has(99)).is_false()


func test_a_new_match_forgets_the_films_shots() -> void:
	P.load_film(_model, FILM)
	P.shoot(_model, FILM)
	_model.clear_match()
	assert_bool(_model.film_shots.is_empty()).is_true()
	assert_bool(_model.stations.is_empty()).is_true()


func test_nothing_kept_names_the_loader_or_the_shooter() -> void:
	P.load_film(_model, FILM)
	P.shoot(_model, FILM)
	assert_int(_model.items[FILM].holder).is_equal(ClientModel.NO_HOLDER)
	assert_int(_model.items[FILM].thrower).is_equal(ClientModel.NO_HOLDER)
