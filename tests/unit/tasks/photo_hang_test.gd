extends GdUnitTestSuite
## The board (the photo ADR §2.7, PD6, PE9, PE11; ARCHITECTURE §9.5): an Interact at the board
## hangs the actor's photo, the hand's, else the belt's. A photo whose shot has a person in it:
## PhotoHung counted (everyone), the photo locked on the board for good (no event; PickUp refuses
## it `unavailable`), then the next subtask done (TaskState, TaskProgress). One without: PhotoHung
## not counted, the photo lies on the board (item_rested `on_station`) and PickUp takes it down.
## No photo is `no_photo`; a done task refuses the camera, the printer and the board `unavailable`
## while the box still gives; a package carrier is refused `two_handed` at the board, though it
## takes a photo off the board onto its belt. Fixture values only.

const P1 := 1
const P2 := 2
const P3 := 3
const PEERS: Array[int] = [P1, P2, P3]
const AWAY := Vector3(30, 0, 0)


func _round() -> Match:
	return FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS)


func _station(game: Match, which: StringName) -> int:
	return FixturePhotoModes.state_of(game).get(which)


## A round where P1 shot the dealt film `shots` times, P2 in the frame when `person`, else away
## with P3, and printed it: the photos lie on the tray.
func _printed(person: bool, shots: int = FixturePhotoModes.FRAMES) -> Match:
	var game := _round()
	FixtureItemModes.stand(game, P2, FixturePhotoModes.IN_FRAME if person else AWAY)
	FixtureItemModes.stand(game, P3, AWAY + Vector3(0, 0, 2))
	FixturePhotoModes.expose(game, P1, FixturePhotoModes.dealt_film(game), shots)
	FixturePhotoModes.use(game, P1, _station(game, &"printer"))
	assert_array(FixturePhotoModes.printed(game)).has_size(shots)
	return game


## `peer` takes `photo` off the tray and hangs it.
func _hang(game: Match, peer: int, photo: ItemState) -> void:
	FixturePhotoModes.take(game, peer, photo)
	FixturePhotoModes.use(game, peer, _station(game, &"board"))


func test_a_photo_with_a_person_is_counted_locked_on_the_board_and_a_subtask_done() -> void:
	var game := _printed(true)
	var photo := FixturePhotoModes.printed(game)[0]
	FixturePhotoModes.take(game, P1, photo)
	var seen := game.view_of(P3).events.size()
	FixturePhotoModes.use(game, P1, _station(game, &"board"))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_empty()
	# No FixtureNote: a locked photo raises no item_rested.
	assert_array(FixtureItemModes.names_after(game, P3, seen)).is_equal(
		[&"PhotoHung", &"TaskState", &"TaskProgress"]
	)
	var board := _station(game, &"board")
	for peer: int in PEERS:
		assert_array(FixturePhotoModes.received(game, peer, &"PhotoHung")).is_equal(
			[{"item": photo.id, "station": board, "counted": true}]
		)
	assert_int(photo.where).is_equal(ItemState.Where.LOCKED)
	assert_vector(photo.position).is_equal(FixturePhotoModes.BOARD_AT)
	assert_object(Items.held_by(game.state, P1)).is_null()
	var task_state := FixturePhotoModes.state_of(game)
	assert_array(Array(task_state.counted)).is_equal([0])
	assert_int(task_state.done_count()).is_equal(1)


func test_a_counted_photo_stays_on_the_board_pick_up_refuses_it() -> void:
	var game := _printed(true)
	var photo := FixturePhotoModes.printed(game)[0]
	_hang(game, P1, photo)
	FixturePhotoModes.take(game, P2, photo)
	assert_array(FixturePhotoModes.reasons(game, P2)).is_equal([&"unavailable"])
	assert_int(photo.where).is_equal(ItemState.Where.LOCKED)
	assert_object(Items.held_by(game.state, P2)).is_null()


func test_a_photo_without_a_person_lies_on_the_board_uncounted_and_comes_down() -> void:
	var game := _printed(false)
	var photo := FixturePhotoModes.printed(game)[0]
	FixturePhotoModes.take(game, P1, photo)
	var seen := game.view_of(P3).events.size()
	FixturePhotoModes.use(game, P1, _station(game, &"board"))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_empty()
	# FixtureNote: the fixture's rule noting the photo's item_rested `on_station`.
	assert_array(FixtureItemModes.names_after(game, P3, seen)).is_equal(
		[&"PhotoHung", &"FixtureNote"]
	)
	assert_array(FixturePhotoModes.received(game, P3, &"PhotoHung")).is_equal(
		[{"item": photo.id, "station": _station(game, &"board"), "counted": false}]
	)
	var note := "rested %d on_station" % photo.id
	(
		assert_bool(
			FixtureModes.notes(game).any(func(text: String) -> bool: return text.begins_with(note))
		)
		. is_true()
	)
	assert_int(photo.where).is_equal(ItemState.Where.GROUND)
	assert_vector(photo.position).is_equal(FixturePhotoModes.BOARD_AT)
	assert_array(Array(FixturePhotoModes.state_of(game).counted)).is_empty()
	FixturePhotoModes.take(game, P2, photo)
	assert_array(FixturePhotoModes.reasons(game, P2)).is_empty()
	assert_object(Items.held_by(game.state, P2)).is_same(photo)


func test_the_belts_photo_hangs_when_the_hand_holds_a_knife() -> void:
	var game := _printed(true)
	var photo := FixturePhotoModes.printed(game)[0]
	FixturePhotoModes.take(game, P1, photo)
	var knife := FixtureItemModes.lay(game, &"knife", Vector3(20, 0, 0))
	FixturePhotoModes.take(game, P1, knife)
	assert_object(Items.belted_by(game.state, P1)).is_same(photo)
	FixturePhotoModes.use(game, P1, _station(game, &"board"))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_empty()
	assert_int(photo.where).is_equal(ItemState.Where.LOCKED)
	assert_object(Items.held_by(game.state, P1)).is_same(knife)
	assert_object(Items.belted_by(game.state, P1)).is_null()


func test_no_photo_or_a_film_is_no_photo() -> void:
	var game := _round()
	var board := _station(game, &"board")
	FixturePhotoModes.use(game, P1, board)
	FixturePhotoModes.take(game, P1, FixturePhotoModes.dealt_film(game))
	FixturePhotoModes.use(game, P1, board)
	assert_array(FixturePhotoModes.reasons(game, P1)).is_equal([&"no_photo", &"no_photo"])
	assert_array(FixturePhotoModes.received(game, P1, &"PhotoHung")).is_empty()


func test_the_last_subtask_leaves_only_the_box_usable() -> void:
	var game := _printed(true)
	for photo: ItemState in FixturePhotoModes.printed(game):
		_hang(game, P1, photo)
	var task_state := FixturePhotoModes.state_of(game)
	assert_bool(task_state.is_done()).is_true()
	assert_array(Array(task_state.counted)).is_equal([0, 1])
	assert_array(FixturePhotoModes.received(game, P3, &"TaskProgress")).has_size(3)
	for which: StringName in [&"camera", &"printer", &"board"]:
		FixturePhotoModes.use(game, P1, _station(game, which))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_equal(
		[&"unavailable", &"unavailable", &"unavailable"]
	)
	FixturePhotoModes.use(game, P1, _station(game, &"film_box"))
	assert_array(FixturePhotoModes.reasons(game, P1)).has_size(3)
	assert_str(Items.held_by(game.state, P1).kind.id).is_equal("film")


func test_a_package_carrier_is_refused_two_handed_but_takes_a_photo_off_the_board() -> void:
	var game := _printed(false)
	var photo := FixturePhotoModes.printed(game)[0]
	_hang(game, P1, photo)
	var package := FixtureItemModes.lay(game, &"package", Vector3(20, 0, 0))
	FixturePhotoModes.take(game, P2, package)
	var other := FixturePhotoModes.printed(game)[1]
	FixturePhotoModes.take(game, P3, other)
	FixturePhotoModes.take(game, P2, photo)
	assert_array(FixturePhotoModes.reasons(game, P2)).is_empty()
	assert_object(Items.belted_by(game.state, P2)).is_same(photo)
	FixturePhotoModes.use(game, P2, _station(game, &"board"))
	assert_array(FixturePhotoModes.reasons(game, P2)).is_equal([&"two_handed"])
	assert_object(Items.belted_by(game.state, P2)).is_same(photo)
	assert_array(FixturePhotoModes.received(game, P2, &"PhotoHung")).has_size(1)
