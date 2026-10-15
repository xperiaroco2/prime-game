extends GdUnitTestSuite
## ClientModel's fold of a shot's record, printed and hung photos (#787, photo P8): a shot keeps a
## copy of its record and is listed on its film; PhotoPrinted binds a photo to its shot and takes
## the shot off the film's list (the frames used stay); a shot is dropped once no film lists it and
## no photo shows it (the host's PhotoTask._prune); PhotoHung lifts the photo out of the hand onto
## the board's lowest free slot, locked when counted; a taken-down uncounted photo frees its slot.

const C := preload("res://tests/fixtures/client/fixture_photo_client.gd")
const FILM := 50
const PHOTO_A := 60
const PHOTO_B := 61
const PHOTO_C := 62

var _model: ClientModel


func before_test() -> void:
	_model = C.dealt()
	C.load_film(_model, FILM)


func test_a_shot_keeps_a_copy_of_its_record_and_is_listed_on_its_film() -> void:
	var record: Array[Dictionary] = [C.row(C.OTHER, Vector3(1, 0, 2))]
	C.shoot(_model, FILM, 7, record)
	record[0]["position"] = Vector3(9, 9, 9)
	assert_bool(_model.shots.has(7)).is_true()
	var shot := _model.shots[7]
	assert_int(shot.film).is_equal(FILM)
	assert_int(shot.station).is_equal(C.CAMERA)
	assert_int(shot.record.size()).is_equal(1)
	assert_vector(shot.record[0]["position"] as Vector3).is_equal(Vector3(1, 0, 2))
	assert_int(shot.record[0]["peer"] as int).is_equal(C.OTHER)
	assert_array(Array(_model.film_pictures[FILM])).contains_exactly([7])


func test_a_print_binds_the_photo_and_moves_the_shot_off_the_film() -> void:
	C.shoot(_model, FILM, 7)
	C.shoot(_model, FILM, 8)
	C.printed(_model, FILM, PHOTO_A, 7, false)
	assert_int(_model.items[PHOTO_A].shot).is_equal(7)
	assert_array(Array(_model.film_pictures[FILM])).contains_exactly([8])
	# The frames used stay: a print never gives a frame back.
	assert_int(_model.stations[C.CAMERA].shots).is_equal(2)
	assert_bool(_model.shots.has(7)).is_true()
	assert_bool(_model.shots.has(8)).is_true()


func test_a_full_print_then_the_films_vanish_keeps_the_photos_shots() -> void:
	C.shoot(_model, FILM, 7)
	C.shoot(_model, FILM, 8)
	C.printed(_model, FILM, PHOTO_A, 7, false)
	C.printed(_model, FILM, PHOTO_B, 8, true)
	assert_bool(_model.film_pictures.has(FILM)).is_false()
	assert_bool(_model.shots.has(7)).is_true()
	assert_bool(_model.shots.has(8)).is_true()


func test_a_photos_vanish_drops_its_shot() -> void:
	C.shoot(_model, FILM, 7)
	C.printed(_model, FILM, PHOTO_A, 7, true)
	C.fold(_model, ItemVanishedEvent.new(PHOTO_A))
	assert_bool(_model.shots.has(7)).is_false()


func test_a_film_vanishing_unprinted_drops_its_shots() -> void:
	C.shoot(_model, FILM, 7)
	C.shoot(_model, FILM, 8)
	C.fold(_model, ItemVanishedEvent.new(FILM))
	assert_bool(_model.shots.is_empty()).is_true()
	assert_bool(_model.film_pictures.is_empty()).is_true()


func test_a_shot_id_seen_again_is_a_new_shot() -> void:
	C.shoot(_model, FILM, 7, [C.row(C.OTHER, Vector3.ZERO)])
	var first := _model.shots[7]
	C.shoot(_model, FILM, 7, [C.row(C.OWN, Vector3.ONE)])
	assert_object(_model.shots[7]).is_not_same(first)
	assert_int(_model.shots[7].record[0]["peer"] as int).is_equal(C.OWN)
	assert_array(Array(_model.film_pictures[FILM])).contains_exactly([7])


func test_a_counted_hang_locks_the_photo_on_the_boards_next_slot() -> void:
	_hold_photo(PHOTO_A)
	C.hang(_model, PHOTO_A, true)
	var photo := _model.items[PHOTO_A]
	assert_int(photo.holder).is_equal(ClientModel.NO_HOLDER)
	assert_bool(photo.belted).is_false()
	assert_int(photo.on_station).is_equal(C.BOARD)
	assert_bool(photo.locked).is_true()
	assert_vector(photo.position).is_equal(_model.stations[C.BOARD].position)
	assert_int(_model.hand_item(C.OWN)).is_equal(-1)
	_hold_photo(PHOTO_B)
	C.hang(_model, PHOTO_B, true)
	assert_array(Array(_model.stations[C.BOARD].hung)).contains_exactly([PHOTO_A, PHOTO_B])


func test_a_taken_down_uncounted_photo_frees_its_slot_for_the_next_hang() -> void:
	_hold_photo(PHOTO_A)
	C.hang(_model, PHOTO_A, false)
	assert_bool(_model.items[PHOTO_A].locked).is_false()
	_hold_photo(PHOTO_B)
	C.hang(_model, PHOTO_B, true)
	C.fold(_model, ItemPickedUpEvent.new(C.OWN, PHOTO_A))
	assert_int(_model.items[PHOTO_A].on_station).is_equal(-1)
	assert_array(Array(_model.stations[C.BOARD].hung)).contains_exactly([-1, PHOTO_B])
	_hold_photo(PHOTO_C)
	C.hang(_model, PHOTO_C, true)
	assert_array(Array(_model.stations[C.BOARD].hung)).contains_exactly([PHOTO_C, PHOTO_B])


func test_the_last_slot_taken_down_leaves_no_trailing_free_slot() -> void:
	_hold_photo(PHOTO_A)
	C.hang(_model, PHOTO_A, false)
	C.fold(_model, ItemPickedUpEvent.new(C.OWN, PHOTO_A))
	assert_int(_model.stations[C.BOARD].hung.size()).is_equal(0)


func test_a_hung_photo_keeps_its_shot() -> void:
	C.shoot(_model, FILM, 7)
	C.printed(_model, FILM, PHOTO_A, 7, true)
	C.fold(_model, ItemPickedUpEvent.new(C.OWN, PHOTO_A))
	C.hang(_model, PHOTO_A, true)
	assert_int(_model.items[PHOTO_A].shot).is_equal(7)
	assert_bool(_model.shots.has(7)).is_true()


func test_clear_match_forgets_the_shots() -> void:
	C.shoot(_model, FILM, 7)
	_model.clear_match()
	assert_bool(_model.shots.is_empty()).is_true()
	assert_bool(_model.film_pictures.is_empty()).is_true()


## Photo `id` spawned and picked up by the own player (its hand empty first: one hangs it).
func _hold_photo(id: int) -> void:
	C.hold(_model, id, &"photo")
