extends GdUnitTestSuite
## The printer (the photo ADR §2.6, PD3, PD16 (a), PE8, PE11; ARCHITECTURE §9.5): an Interact at
## the printer prints every shot of the actor's exposed film (the hand's, else the belt's), once
## each, in shot order: per shot ItemSpawned on the tray, then PhotoPrinted (the photo, the shot);
## then the film vanishes (ItemVanished, last). Unshot frames print nothing; a fresh film or none
## is `nothing_to_print`; a done task `unavailable`; a package carrier `two_handed`, though it takes
## a photo off the tray onto its belt. Fixture values only.

const P1 := 1
const P2 := 2
const P3 := 3
const PEERS: Array[int] = [P1, P2, P3]
const AWAY := Vector3(30, 0, 0)


func _round() -> Match:
	return FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS)


func _printer(game: Match) -> int:
	return FixturePhotoModes.state_of(game).printer


## A round where P1 shot the dealt film `shots` times with P2 in the frame and holds it, exposed.
func _exposed(shots: int = FixturePhotoModes.FRAMES) -> Match:
	var game := _round()
	FixtureItemModes.stand(game, P2, FixturePhotoModes.IN_FRAME)
	FixtureItemModes.stand(game, P3, AWAY)
	FixturePhotoModes.expose(game, P1, FixturePhotoModes.dealt_film(game), shots)
	return game


func test_a_print_makes_one_photo_per_shot_in_shot_order_then_the_film_vanishes() -> void:
	var game := _exposed()
	var film := FixturePhotoModes.dealt_film(game)
	var film_id := film.id
	var seen := game.view_of(P3).events.size()
	FixturePhotoModes.use(game, P1, _printer(game))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_empty()
	# FixtureNote: the fixture's rule noting item_rested, which follows each PhotoPrinted (PE11).
	(
		assert_array(FixtureItemModes.names_after(game, P3, seen))
		. is_equal(
			[
				&"ItemSpawned",
				&"PhotoPrinted",
				&"FixtureNote",
				&"ItemSpawned",
				&"PhotoPrinted",
				&"FixtureNote",
				&"ItemVanished",
			]
		)
	)
	var photos := FixturePhotoModes.printed(game)
	assert_int(photos.size()).is_equal(FixturePhotoModes.FRAMES)
	var sent := FixturePhotoModes.received(game, P3, &"PhotoPrinted")
	assert_array(sent).is_equal(
		[{"item": photos[0].id, "shot": 0}, {"item": photos[1].id, "shot": 1}]
	)
	for photo: ItemState in photos:
		assert_str(photo.kind.id).is_equal("photo")
		assert_int(photo.where).is_equal(ItemState.Where.GROUND)
		assert_vector(photo.position).is_equal(FixturePhotoModes.PHOTO_AT)
		var note := "rested %d spawn" % photo.id
		(
			assert_bool(
				FixtureModes.notes(game).any(
					func(text: String) -> bool: return text.begins_with(note)
				)
			)
			. is_true()
		)
	var vanished: Dictionary = FixturePhotoModes.received(game, P3, &"ItemVanished")[-1]
	assert_int(vanished["item"]).is_equal(film_id)
	assert_bool(game.state.items.has(film_id)).is_false()
	assert_object(Items.held_by(game.state, P1)).is_null()
	for peer: int in PEERS:
		assert_array(FixturePhotoModes.received(game, peer, &"PhotoPrinted")).is_equal(sent)


func test_the_film_and_its_shots_leave_the_task_state_and_the_photos_keep_theirs() -> void:
	var game := _exposed()
	var film_id := FixturePhotoModes.dealt_film(game).id
	FixturePhotoModes.use(game, P1, _printer(game))
	var task_state := FixturePhotoModes.state_of(game)
	assert_bool(task_state.films.has(film_id)).is_false()
	var photos := FixturePhotoModes.printed(game)
	assert_int(task_state.print_of(photos[0]).shot).is_equal(0)
	assert_int(task_state.print_of(photos[1]).shot).is_equal(1)
	assert_array(task_state.shots.keys()).contains_exactly_in_any_order([0, 1])


func test_a_film_shot_once_prints_one_photo() -> void:
	var game := _exposed(1)
	FixturePhotoModes.use(game, P1, _printer(game))
	assert_array(FixturePhotoModes.received(game, P3, &"PhotoPrinted")).is_equal(
		[{"item": FixturePhotoModes.printed(game)[0].id, "shot": 0}]
	)


func test_the_hands_exposed_film_prints_before_the_belts() -> void:
	var game := _exposed()
	var first := FixturePhotoModes.dealt_film(game)
	var second := FixturePhotoModes.give_film(game, P1)
	assert_object(Items.belted_by(game.state, P1)).is_same(first)
	FixtureItemModes.stand(game, P2, FixturePhotoModes.IN_FRAME)
	FixturePhotoModes.expose(game, P1, second, 1)
	assert_object(Items.held_by(game.state, P1)).is_same(second)
	FixturePhotoModes.use(game, P1, _printer(game))
	assert_array(FixturePhotoModes.received(game, P3, &"PhotoPrinted")).is_equal(
		[{"item": FixturePhotoModes.printed(game)[0].id, "shot": 2}]
	)
	assert_bool(game.state.items.has(second.id)).is_false()
	assert_object(Items.belted_by(game.state, P1)).is_same(first)


func test_a_fresh_film_in_the_hand_leaves_the_belts_exposed_one_to_print() -> void:
	var game := _exposed()
	var exposed := FixturePhotoModes.dealt_film(game)
	var fresh := FixturePhotoModes.give_film(game, P1)
	assert_object(Items.belted_by(game.state, P1)).is_same(exposed)
	FixturePhotoModes.use(game, P1, _printer(game))
	assert_array(FixturePhotoModes.printed(game)).has_size(FixturePhotoModes.FRAMES)
	assert_bool(game.state.items.has(exposed.id)).is_false()
	assert_object(Items.held_by(game.state, P1)).is_same(fresh)
	assert_object(Items.belted_by(game.state, P1)).is_null()


func test_a_fresh_film_or_none_is_nothing_to_print() -> void:
	var game := _round()
	FixturePhotoModes.use(game, P1, _printer(game))
	FixturePhotoModes.take(game, P1, FixturePhotoModes.dealt_film(game))
	FixturePhotoModes.use(game, P1, _printer(game))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_equal(
		[&"nothing_to_print", &"nothing_to_print"]
	)
	assert_array(FixturePhotoModes.received(game, P1, &"PhotoPrinted")).is_empty()
	assert_bool(game.state.items.has(FixturePhotoModes.dealt_film(game).id)).is_true()


func test_a_done_task_refuses_the_print_unavailable() -> void:
	var game := _exposed()
	FixturePhotoModes.state_of(game).counted = PackedInt32Array([7, 8])
	FixturePhotoModes.use(game, P1, _printer(game))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_equal([&"unavailable"])
	assert_array(FixturePhotoModes.received(game, P1, &"PhotoPrinted")).is_empty()


func test_a_package_carrier_is_refused_two_handed_but_takes_a_photo_off_the_tray() -> void:
	var game := _exposed()
	FixturePhotoModes.use(game, P1, _printer(game))
	var package := FixtureItemModes.lay(game, &"package", Vector3(20, 0, 0))
	FixturePhotoModes.take(game, P2, package)
	FixturePhotoModes.use(game, P2, _printer(game))
	assert_array(FixturePhotoModes.reasons(game, P2)).is_equal([&"two_handed"])
	var photo := FixturePhotoModes.printed(game)[0]
	FixturePhotoModes.take(game, P2, photo)
	assert_array(FixturePhotoModes.reasons(game, P2)).is_equal([&"two_handed"])
	assert_object(Items.held_by(game.state, P2)).is_same(package)
	assert_object(Items.belted_by(game.state, P2)).is_same(photo)
