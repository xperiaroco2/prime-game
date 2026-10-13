extends GdUnitTestSuite
## The photo task's caps (the photo ADR §2.5, §2.6, PE10, PE12; ARCHITECTURE §9.4.2, §9.5): at the
## film kind's cap a box take first vanishes the loose film with the lowest PhotoTask.cap_tier (0
## a fresh film, 1 one with shots, 2 the camera's), then the one that has lain longest, so a fresh
## film that rested later goes before an older exposed one and the camera's film only when no
## other lies loose; at the photo kind's cap each print first vanishes the oldest loose photo
## (every photo tier 0, with a person or without). The task drops the entries of what vanished in
## that command (films, prints, the shots none of the rest shows, the camera's film), so a new
## film that gets a vanished film's id (ids reused past MAX_ITEM_ID) is fresh: nothing to print,
## and the camera loads it. The caps are lowered at runtime to keep the scenes small. Fixture
## values only.
##
## Seen failing without the code (#782): with GiveItem._first_loose ordering by rest tick and id
## only, the first two tests fail (the older exposed film vanishes); without the _prune call after
## the box's give_new, the camera's film tests and the recycled-id test fail (`films` keeps the
## vanished film, `loaded` its item); without the one after the print, the photo cap test fails
## (`prints` and `shots` keep the vanished photos').

const P1 := 1
const P2 := 2
const P3 := 3
const PEERS: Array[int] = [P1, P2, P3]
const AWAY := Vector3(30, 0, 0)


func _round() -> Match:
	return FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS)


func _station(game: Match, which: StringName) -> int:
	return FixturePhotoModes.state_of(game).get(which)


func _cap(game: Match, kind_id: StringName, most: int) -> void:
	game.mode.find_item_kind(kind_id).max_items = most


## A round where P1 shot the dealt film `shots` times with P2 in the frame and put it down: it
## lies exposed in front of P1, P1's hands empty.
func _exposed_down(shots: int = 1) -> Match:
	var game := _round()
	FixtureItemModes.stand(game, P2, FixturePhotoModes.IN_FRAME)
	FixtureItemModes.stand(game, P3, AWAY)
	FixturePhotoModes.expose(game, P1, FixturePhotoModes.dealt_film(game), shots)
	FixturePhotoModes.put_down_at(game, P1)
	assert_int(FixturePhotoModes.dealt_film(game).where).is_equal(ItemState.Where.GROUND)
	return game


func _vanished(game: Match) -> Array[int]:
	var found: Array[int] = []
	for event: Dictionary in FixturePhotoModes.received(game, P3, &"ItemVanished"):
		var item: int = event["item"]
		found.append(item)
	return found


func test_a_fresh_film_that_rested_later_vanishes_before_an_older_exposed_one() -> void:
	var game := _exposed_down()
	var exposed := FixturePhotoModes.dealt_film(game)
	var fresh := FixtureItemModes.lay(game, &"film", AWAY + Vector3(0, 0, 4))
	exposed.rest_tick = 1
	fresh.rest_tick = 50
	_cap(game, &"film", 2)
	FixturePhotoModes.use(game, P2, _station(game, &"film_box"))
	assert_array(FixturePhotoModes.reasons(game, P2)).is_empty()
	assert_array(_vanished(game)).is_equal([fresh.id])
	assert_bool(game.state.items.has(exposed.id)).is_true()
	assert_object(FixturePhotoModes.state_of(game).film_of(exposed)).is_not_null()
	assert_str(Items.held_by(game.state, P2).kind.id).is_equal("film")


func test_the_cameras_film_stays_while_another_lies_loose() -> void:
	var game := _exposed_down()
	var exposed := FixturePhotoModes.dealt_film(game)
	var loaded := FixturePhotoModes.give_film(game, P1)
	FixturePhotoModes.use(game, P1, _station(game, &"camera"))
	var task_state := FixturePhotoModes.state_of(game)
	assert_object(task_state.loaded).is_same(loaded)
	loaded.rest_tick = 1
	exposed.rest_tick = 50
	_cap(game, &"film", 2)
	FixturePhotoModes.use(game, P2, _station(game, &"film_box"))
	assert_array(_vanished(game)).is_equal([exposed.id])
	assert_object(task_state.loaded).is_same(loaded)
	assert_bool(task_state.films.has(exposed.id)).is_false()
	assert_array(task_state.shots.keys()).is_empty()


func test_the_cameras_film_goes_when_no_other_lies_loose_and_the_camera_empties() -> void:
	var game := _round()
	var loaded := FixturePhotoModes.dealt_film(game)
	FixturePhotoModes.take(game, P1, loaded)
	FixturePhotoModes.use(game, P1, _station(game, &"camera"))
	var task_state := FixturePhotoModes.state_of(game)
	assert_object(task_state.loaded).is_same(loaded)
	_cap(game, &"film", 1)
	FixturePhotoModes.use(game, P2, _station(game, &"film_box"))
	assert_array(_vanished(game)).is_equal([loaded.id])
	assert_object(task_state.loaded).is_null()


func test_a_print_at_the_photo_cap_vanishes_the_oldest_photo_before_each_spawn() -> void:
	var game := _exposed_down(FixturePhotoModes.FRAMES)
	FixturePhotoModes.take(game, P1, FixturePhotoModes.dealt_film(game))
	FixturePhotoModes.use(game, P1, _station(game, &"printer"))
	var old := FixturePhotoModes.printed(game)
	assert_array(old).has_size(FixturePhotoModes.FRAMES)
	var second := FixturePhotoModes.give_film(game, P1)
	FixtureItemModes.stand(game, P2, FixturePhotoModes.IN_FRAME)
	FixturePhotoModes.expose(game, P1, second, FixturePhotoModes.FRAMES)
	_cap(game, &"photo", FixturePhotoModes.FRAMES)
	var seen := game.view_of(P3).events.size()
	FixturePhotoModes.use(game, P1, _station(game, &"printer"))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_empty()
	(
		assert_array(FixtureItemModes.names_after(game, P3, seen))
		. is_equal(
			[
				&"ItemVanished",
				&"ItemSpawned",
				&"PhotoPrinted",
				&"FixtureNote",
				&"ItemVanished",
				&"ItemSpawned",
				&"PhotoPrinted",
				&"FixtureNote",
				&"ItemVanished",
			]
		)
	)
	assert_array(_vanished(game).slice(-3)).is_equal([old[0].id, old[1].id, second.id])
	var task_state := FixturePhotoModes.state_of(game)
	var fresh := FixturePhotoModes.printed(game).slice(FixturePhotoModes.FRAMES)
	assert_array(task_state.prints.keys()).contains_exactly_in_any_order([fresh[0].id, fresh[1].id])
	assert_array(task_state.shots.keys()).contains_exactly_in_any_order([2, 3])
	assert_bool(task_state.films.has(second.id)).is_false()


func test_a_new_film_on_a_vanished_films_id_is_fresh() -> void:
	var game := _exposed_down()
	var exposed := FixturePhotoModes.dealt_film(game)
	var old_id := exposed.id
	game.state.skip_item_ids_to(MatchState.MAX_ITEM_ID + 1)
	_cap(game, &"film", 1)
	FixturePhotoModes.use(game, P1, _station(game, &"film_box"))
	assert_array(_vanished(game)).is_equal([old_id])
	var made := Items.held_by(game.state, P1)
	assert_int(made.id).is_equal(old_id)
	var task_state := FixturePhotoModes.state_of(game)
	assert_bool(task_state.films.has(old_id)).is_false()
	assert_array(task_state.shots.keys()).is_empty()
	FixturePhotoModes.use(game, P1, _station(game, &"printer"))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_equal([&"nothing_to_print"])
	FixturePhotoModes.use(game, P1, _station(game, &"camera"))
	assert_array(FixturePhotoModes.reasons(game, P1)).has_size(1)
	assert_array(FixturePhotoModes.received(game, P3, &"FilmLoaded").slice(-1)).is_equal(
		[{"station": _station(game, &"camera"), "item": old_id}]
	)
	assert_object(task_state.loaded).is_same(made)


func test_every_photo_is_tier_0_with_a_person_or_without() -> void:
	var game := _round()
	FixtureItemModes.stand(game, P3, AWAY)
	FixtureItemModes.stand(game, P2, FixturePhotoModes.IN_FRAME)
	var film := FixturePhotoModes.dealt_film(game)
	FixturePhotoModes.take(game, P1, film)
	var camera := _station(game, &"camera")
	FixturePhotoModes.use(game, P1, camera)
	FixturePhotoModes.use(game, P1, camera)
	FixtureItemModes.stand(game, P2, AWAY + Vector3(0, 0, 2))
	FixturePhotoModes.use(game, P1, camera)
	FixturePhotoModes.take(game, P1, film)
	FixturePhotoModes.use(game, P1, _station(game, &"printer"))
	var photos := FixturePhotoModes.printed(game)
	var task_state := FixturePhotoModes.state_of(game)
	var type := FixturePhotoModes.type_of(game.mode)
	assert_bool(task_state.shots[task_state.print_of(photos[0]).shot].has_person).is_true()
	assert_bool(task_state.shots[task_state.print_of(photos[1]).shot].has_person).is_false()
	for photo: ItemState in photos:
		assert_int(type.cap_tier(game.state, photo)).is_equal(0)
