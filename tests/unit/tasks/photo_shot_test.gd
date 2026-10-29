extends GdUnitTestSuite
## The photo camera's shot (the photo ADR §2.3, §3.2, §3.3, PE2, PE3, PE5; ARCHITECTURE §9.5): an
## Interact at a loaded camera takes the film's next shot; a living player counts when its feet lie
## outside the camera's cylinder and its head (feet plus the eye height) lies in the PhotoFrame
## with a clear line from the lens; the record holds the living and the knocked down within range_m
## plus RECORD_MARGIN_M of the lens, feet outside the cylinder, in peer order; ShotTaken to everyone
## never says whether a person counted. The fixture's camera looks along +Z: at 6 m the frame's
## half-width is 6 · 1.5 · tan 30° ≈ 5.196 m. Fixture values only.

const P1 := 1
const P2 := 2
const P3 := 3
const PEERS: Array[int] = [P1, P2, P3]
## Beyond range_m + RECORD_MARGIN_M of the lens: no row.
const FAR := Vector3(30, 0, 0)


## P1 takes the dealt film and loads the camera; P2 stands at `subject`, P3 far away; P1 shoots.
func _shot(subject: Vector3, world: WorldQuery = null, life := PlayerState.Life.ALIVE) -> Match:
	var game := FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS, {}, world)
	FixturePhotoModes.take(game, P1, FixturePhotoModes.dealt_film(game))
	FixturePhotoModes.use(game, P1, FixturePhotoModes.camera_of(game))
	FixtureItemModes.stand(game, P2, subject)
	FixtureItemModes.stand(game, P3, FAR)
	game.state.player(P2).life = life
	FixturePhotoModes.use(game, P1, FixturePhotoModes.camera_of(game))
	return game


func _subjects(game: Match) -> PackedInt32Array:
	return FixturePhotoModes.state_of(game).shots[0].subjects


func _rows(game: Match) -> Array:
	var taken := FixturePhotoModes.received(game, P3, &"ShotTaken")
	assert_int(taken.size()).is_equal(1)
	return taken[0]["record"] if not taken.is_empty() else []


func _row(game: Match, peer: int) -> Dictionary:
	var player := game.state.player(peer)
	return {
		"peer": peer,
		"position": player.position,
		"facing": player.facing,
		"downed": player.life == PlayerState.Life.DOWNED,
		"crouched": player.crouched,
		"held_item": player.held_item,
		"belt_item": player.belt_item,
		"belt_item2": player.belt_item2,
	}


func test_a_player_in_the_frame_counts_and_everyone_gets_the_same_shot() -> void:
	var game := _shot(FixturePhotoModes.IN_FRAME)
	var task_state := FixturePhotoModes.state_of(game)
	var shot := task_state.shots[0]
	var film := FixturePhotoModes.dealt_film(game)
	assert_array(Array(shot.subjects)).is_equal([P2])
	assert_bool(shot.has_person).is_true()
	assert_int(shot.film).is_equal(film.id)
	assert_array(Array(task_state.film_of(film).shots)).is_equal([0])
	var expected := {
		"station": FixturePhotoModes.camera_of(game),
		"film": film.id,
		"shot": 0,
		"record": [_row(game, P2)],
	}
	for peer: int in PEERS:
		assert_array(FixturePhotoModes.received(game, peer, &"ShotTaken")).is_equal([expected])


func test_the_shot_never_names_whether_a_person_counted() -> void:
	var game := _shot(FixturePhotoModes.IN_FRAME)
	var sent: Dictionary = FixturePhotoModes.received(game, P3, &"ShotTaken")[0]
	assert_array(sent.keys()).contains_exactly_in_any_order(["station", "film", "shot", "record"])


func test_a_head_just_inside_the_frames_edge_counts_and_just_outside_does_not() -> void:
	var half := 6.0 * FixturePhotoModes.ASPECT * tan(deg_to_rad(FixturePhotoModes.FOV_DEG / 2.0))
	var inside := _shot(FixturePhotoModes.IN_FRAME + Vector3(half - 0.01, 0, 0))
	assert_array(Array(_subjects(inside))).is_equal([P2])
	var outside := _shot(FixturePhotoModes.IN_FRAME + Vector3(half + 0.01, 0, 0))
	assert_array(Array(_subjects(outside))).is_empty()
	assert_array(_rows(outside)).is_equal([_row(outside, P2)])


func test_the_top_and_bottom_edges_count_a_head_just_inside_only() -> void:
	# The head is the feet plus the eye height, the lens at the eye height: a feet height of dy is a
	# head dy above or below the lens's, and the half-height at 6 m is 6 · tan(fov / 2).
	var half := 6.0 * tan(deg_to_rad(FixturePhotoModes.FOV_DEG / 2.0))
	for sign_of: float in [1.0, -1.0]:
		var inside := _shot(FixturePhotoModes.IN_FRAME + Vector3(0, sign_of * (half - 0.01), 0))
		assert_array(Array(_subjects(inside))).is_equal([P2])
		var outside := _shot(FixturePhotoModes.IN_FRAME + Vector3(0, sign_of * (half + 0.01), 0))
		assert_array(Array(_subjects(outside))).is_empty()


func test_a_wall_between_the_lens_and_the_head_hides_it() -> void:
	var wall := FlatWorldQuery.new().add_wall(AABB(Vector3(-1, 0, 23), Vector3(2, 3, 0.5)))
	var game := _shot(FixturePhotoModes.IN_FRAME, wall)
	assert_array(Array(_subjects(game))).is_empty()
	assert_array(_rows(game)).is_equal([_row(game, P2)])


func test_a_crouched_head_hidden_by_cover_a_standing_head_clears_does_not_count() -> void:
	# The crouch ADR, KE2: a crouched subject's head is its feet plus crouch_eye_height_m (1 m).
	# A 1.3 m wall just before it hides that head from the lens (1.6 m up) but not a standing one;
	# its record row says crouched either way, so the picture draws it crouched.
	var wall := FlatWorldQuery.new().add_wall(AABB(Vector3(-1, 0, 24.5), Vector3(2, 1.3, 0.5)))
	var standing := _shot(FixturePhotoModes.IN_FRAME, wall)
	assert_array(Array(_subjects(standing))).is_equal([P2])
	var game := FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS, {}, wall)
	FixturePhotoModes.take(game, P1, FixturePhotoModes.dealt_film(game))
	FixturePhotoModes.use(game, P1, FixturePhotoModes.camera_of(game))
	FixtureItemModes.stand(game, P2, FixturePhotoModes.IN_FRAME)
	FixtureItemModes.stand(game, P3, FAR)
	game.state.player(P2).crouched = true
	FixturePhotoModes.use(game, P1, FixturePhotoModes.camera_of(game))
	assert_array(Array(_subjects(game))).is_empty()
	assert_array(_rows(game)).is_equal([_row(game, P2)])
	assert_bool(_rows(game)[0]["crouched"]).is_true()


func test_a_knocked_down_player_never_counts_but_has_a_downed_row() -> void:
	var game := _shot(FixturePhotoModes.IN_FRAME, null, PlayerState.Life.DOWNED)
	assert_array(Array(_subjects(game))).is_empty()
	assert_bool(FixturePhotoModes.state_of(game).shots[0].has_person).is_false()
	var rows := _rows(game)
	assert_int(rows.size()).is_equal(1)
	assert_bool(rows[0]["downed"]).is_true()


func test_a_dead_player_has_no_row() -> void:
	var game := _shot(FixturePhotoModes.IN_FRAME, null, PlayerState.Life.DEAD)
	assert_array(Array(_subjects(game))).is_empty()
	assert_array(_rows(game)).is_empty()


func test_a_player_in_the_cameras_cylinder_neither_counts_nor_has_a_row() -> void:
	var game := _shot(FixturePhotoModes.CAMERA_AT + Vector3(0.3, 0, 0.2))
	assert_array(Array(_subjects(game))).is_empty()
	assert_array(_rows(game)).is_empty()


func test_beyond_range_no_count_and_beyond_the_margin_no_row() -> void:
	var lens_z := FixturePhotoModes.CAMERA_AT.z
	var past_range := _shot(Vector3(0, 0, lens_z + FixturePhotoModes.RANGE_M + 0.5))
	assert_array(Array(_subjects(past_range))).is_empty()
	assert_array(_rows(past_range)).is_equal([_row(past_range, P2)])
	var reach := FixturePhotoModes.RANGE_M + PhotoTask.RECORD_MARGIN_M
	var past_margin := _shot(Vector3(0, 0, lens_z + reach + 0.5))
	assert_array(_rows(past_margin)).is_empty()


func test_a_row_names_the_items_its_player_carries() -> void:
	var game := FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS)
	FixturePhotoModes.take(game, P1, FixturePhotoModes.dealt_film(game))
	FixturePhotoModes.use(game, P1, FixturePhotoModes.camera_of(game))
	var tool := FixtureItemModes.lay(game, &"tool", Vector3(20, 0, 0))
	FixturePhotoModes.take(game, P2, tool)
	FixtureItemModes.stand(game, P2, FixturePhotoModes.IN_FRAME)
	FixtureItemModes.stand(game, P3, FixturePhotoModes.IN_FRAME + Vector3(1, 0, 0))
	game.state.player(P3).facing = Vector3.LEFT
	FixturePhotoModes.use(game, P1, FixturePhotoModes.camera_of(game))
	var rows := _rows(game)
	assert_array(rows).is_equal([_row(game, P2), _row(game, P3)])
	assert_int(rows[0]["held_item"]).is_equal(tool.id)
	assert_vector(rows[1]["facing"]).is_equal(Vector3.LEFT)
	assert_array(Array(_subjects(game))).is_equal([P2, P3])


func test_shot_ids_follow_each_other_across_films() -> void:
	var game := _shot(FixturePhotoModes.IN_FRAME)
	var camera := FixturePhotoModes.camera_of(game)
	FixturePhotoModes.use(game, P1, camera)
	FixturePhotoModes.take(game, P2, FixturePhotoModes.dealt_film(game))
	FixturePhotoModes.give_film(game, P2)
	FixturePhotoModes.use(game, P2, camera)
	FixturePhotoModes.use(game, P2, camera)
	var ids: Array[int] = []
	for sent: Dictionary in FixturePhotoModes.received(game, P3, &"ShotTaken"):
		ids.append(sent["shot"])
	assert_array(ids).is_equal([0, 1, 2])


func test_the_load_and_the_shot_each_emit_one_event() -> void:
	var game := FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS)
	FixturePhotoModes.take(game, P1, FixturePhotoModes.dealt_film(game))
	var seen := game.view_of(P3).events.size()
	FixturePhotoModes.use(game, P1, FixturePhotoModes.camera_of(game))
	assert_array(_names_after(game, seen)).is_equal([&"FilmLoaded"])
	seen = game.view_of(P3).events.size()
	FixturePhotoModes.use(game, P1, FixturePhotoModes.camera_of(game))
	assert_array(_names_after(game, seen)).is_equal([&"ShotTaken"])


## The events P3 received after its first `skip`, but the fixture's notes (its item_rested
## reaction's FixtureNote).
func _names_after(game: Match, skip: int) -> Array[StringName]:
	var found: Array[StringName] = []
	for event_name: StringName in FixtureItemModes.names_after(game, P3, skip):
		if event_name != &"FixtureNote":
			found.append(event_name)
	return found
