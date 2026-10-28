extends GdUnitTestSuite
## The photo camera's load and its film (the photo ADR §2.2, PD16, PE6, PE11, PE16, PE17;
## ARCHITECTURE §9.5): an Interact at an empty camera lays the actor's fresh film, from the hand
## or else the belt, on the camera (FilmLoaded to everyone, no ItemPlaced); the camera holds it only
## while that very item lies there with the move serial the load left, so any lift (a pick-up, a
## take onto a package carrier's belt, PickUp's exchange) or a vanish with a recycled id empties
## it, in the load's tick too; the refusals no_film, film_exposed, no_frames_left and unavailable,
## each after the station conditions. Fixture values only.

const P1 := 1
const P2 := 2
const P3 := 3
const PEERS: Array[int] = [P1, P2, P3]


func _round() -> Match:
	return FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS)


## P1 takes the dealt film and loads the camera with it.
func _loaded() -> Match:
	var game := _round()
	FixturePhotoModes.take(game, P1, FixturePhotoModes.dealt_film(game))
	FixturePhotoModes.use(game, P1, FixturePhotoModes.camera_of(game))
	return game


func _shots(game: Match) -> int:
	return FixturePhotoModes.received(game, P3, &"ShotTaken").size()


func test_a_film_in_the_hand_loads_the_camera() -> void:
	var game := _loaded()
	var film := FixturePhotoModes.dealt_film(game)
	var camera := FixturePhotoModes.camera_of(game)
	for peer: int in PEERS:
		assert_array(FixturePhotoModes.received(game, peer, &"FilmLoaded")).is_equal(
			[{"station": camera, "item": film.id}]
		)
	assert_int(film.where).is_equal(ItemState.Where.GROUND)
	assert_vector(film.position).is_equal(FixturePhotoModes.CAMERA_AT)
	assert_object(Items.held_by(game.state, P1)).is_null()
	assert_array(FixturePhotoModes.received(game, P3, &"ItemPlaced")).is_empty()
	assert_array(FixturePhotoModes.reasons(game, P1)).is_empty()
	assert_object(FixturePhotoModes.state_of(game).loaded).is_same(film)


func test_a_film_on_the_belt_loads_when_the_hand_holds_another_item() -> void:
	var game := _round()
	var film := FixturePhotoModes.dealt_film(game)
	FixturePhotoModes.take(game, P1, film)
	FixturePhotoModes.take(game, P1, FixtureItemModes.lay(game, &"tool", Vector3(20, 0, 0)))
	assert_object(Items.belted_by(game.state, P1)).is_same(film)
	FixturePhotoModes.use(game, P1, FixturePhotoModes.camera_of(game))
	assert_array(FixturePhotoModes.received(game, P1, &"FilmLoaded")).has_size(1)
	assert_vector(film.position).is_equal(FixturePhotoModes.CAMERA_AT)
	assert_object(Items.belted_by(game.state, P1)).is_null()
	assert_str(Items.held_by(game.state, P1).kind.id).is_equal("tool")


func test_no_film_refuses_a_load_with_nothing_or_another_item() -> void:
	var game := _round()
	var camera := FixturePhotoModes.camera_of(game)
	FixturePhotoModes.use(game, P1, camera)
	FixturePhotoModes.take(game, P1, FixtureItemModes.lay(game, &"tool", Vector3(20, 0, 0)))
	FixturePhotoModes.use(game, P1, camera)
	assert_array(FixturePhotoModes.reasons(game, P1)).is_equal([&"no_film", &"no_film"])
	assert_array(FixturePhotoModes.received(game, P1, &"FilmLoaded")).is_empty()


func test_a_shot_on_a_loaded_camera_then_no_frames_left() -> void:
	var game := _loaded()
	var camera := FixturePhotoModes.camera_of(game)
	for i in FixturePhotoModes.FRAMES:
		FixturePhotoModes.use(game, P2, camera)
	assert_int(_shots(game)).is_equal(FixturePhotoModes.FRAMES)
	FixturePhotoModes.use(game, P2, camera)
	assert_array(FixturePhotoModes.reasons(game, P2)).is_equal([&"no_frames_left"])
	assert_int(_shots(game)).is_equal(FixturePhotoModes.FRAMES)


func test_an_exposed_film_is_refused_and_a_fresh_one_beside_it_loads() -> void:
	var game := _loaded()
	var camera := FixturePhotoModes.camera_of(game)
	var film := FixturePhotoModes.dealt_film(game)
	FixturePhotoModes.use(game, P2, camera)
	FixturePhotoModes.take(game, P2, film)
	FixturePhotoModes.use(game, P2, camera)
	assert_array(FixturePhotoModes.reasons(game, P2)).is_equal([&"film_exposed"])
	var fresh := FixturePhotoModes.give_film(game, P2)
	assert_object(Items.belted_by(game.state, P2)).is_same(film)
	FixturePhotoModes.use(game, P2, camera)
	(
		assert_array(FixturePhotoModes.received(game, P2, &"FilmLoaded"))
		. is_equal(
			[
				{"station": camera, "item": film.id},
				{"station": camera, "item": fresh.id},
			]
		)
	)


func test_the_exposed_film_keeps_its_shots_whoever_carries_it() -> void:
	var game := _loaded()
	var camera := FixturePhotoModes.camera_of(game)
	var film := FixturePhotoModes.dealt_film(game)
	FixturePhotoModes.use(game, P2, camera)
	FixturePhotoModes.take(game, P3, film)
	FixturePhotoModes.put_down_at(game, P3)
	FixturePhotoModes.take(game, P1, film)
	FixturePhotoModes.use(game, P1, camera)
	assert_array(FixturePhotoModes.reasons(game, P1)).is_equal([&"film_exposed"])
	assert_int(FixturePhotoModes.state_of(game).film_of(film).shots.size()).is_equal(1)


func test_a_pick_up_of_the_loaded_film_empties_the_camera() -> void:
	var game := _loaded()
	var camera := FixturePhotoModes.camera_of(game)
	FixturePhotoModes.take(game, P2, FixturePhotoModes.dealt_film(game))
	FixturePhotoModes.use(game, P3, camera)
	assert_array(FixturePhotoModes.reasons(game, P3)).is_equal([&"no_film"])
	assert_int(_shots(game)).is_equal(0)
	FixturePhotoModes.use(game, P2, camera)
	assert_array(FixturePhotoModes.received(game, P2, &"FilmLoaded")).has_size(2)


func test_a_package_carriers_pick_up_onto_the_belt_empties_the_camera() -> void:
	var game := _loaded()
	var film := FixturePhotoModes.dealt_film(game)
	FixturePhotoModes.take(game, P2, FixtureItemModes.lay(game, &"package", Vector3(20, 0, 0)))
	FixturePhotoModes.take(game, P2, film)
	assert_object(Items.belted_by(game.state, P2)).is_same(film)
	FixturePhotoModes.use(game, P3, FixturePhotoModes.camera_of(game))
	assert_array(FixturePhotoModes.reasons(game, P3)).is_equal([&"no_film"])
	assert_int(_shots(game)).is_equal(0)


func test_pick_ups_exchange_leaves_another_item_on_the_camera_and_empties_it() -> void:
	var game := _loaded()
	var film := FixturePhotoModes.dealt_film(game)
	var other := FixturePhotoModes.give_film(game, P2)
	# All three places full (GDD §6): the take exchanges the hand item for the picked one.
	FixturePhotoModes.take(game, P2, FixtureItemModes.lay(game, &"tool", Vector3(21, 0, 0)))
	var tool := FixtureItemModes.lay(game, &"tool", Vector3(20, 0, 0))
	FixturePhotoModes.take(game, P2, tool)
	assert_object(Items.belted_by(game.state, P2)).is_same(other)
	FixturePhotoModes.take(game, P2, film)
	assert_object(Items.held_by(game.state, P2)).is_same(film)
	assert_vector(tool.position).is_equal(FixturePhotoModes.CAMERA_AT)
	FixturePhotoModes.use(game, P3, FixturePhotoModes.camera_of(game))
	assert_array(FixturePhotoModes.reasons(game, P3)).is_equal([&"no_film"])
	assert_int(_shots(game)).is_equal(0)


func test_a_pick_up_and_put_down_in_the_loads_tick_empties_the_camera() -> void:
	var game := _loaded()
	var film := FixturePhotoModes.dealt_film(game)
	var tick := game.ticked_through()
	FixturePhotoModes.take(game, P2, film)
	FixturePhotoModes.put_down_at(game, P2)
	assert_int(film.where).is_equal(ItemState.Where.GROUND)
	assert_int(game.ticked_through()).is_equal(tick)
	FixturePhotoModes.use(game, P3, FixturePhotoModes.camera_of(game))
	assert_array(FixturePhotoModes.reasons(game, P3)).is_equal([&"no_film"])
	assert_int(_shots(game)).is_equal(0)
	# The next Interact with a fresh film is a load, not a shot.
	var fresh := FixturePhotoModes.give_film(game, P3)
	FixturePhotoModes.use(game, P3, FixturePhotoModes.camera_of(game))
	assert_int(_shots(game)).is_equal(0)
	assert_array(FixturePhotoModes.received(game, P3, &"FilmLoaded")).has_size(2)
	assert_object(FixturePhotoModes.state_of(game).loaded).is_same(fresh)


func test_a_pick_up_then_a_death_drop_back_on_the_camera_empties_it() -> void:
	var killers: Array[FixtureKillTick] = []
	var game := FixturePhotoModes.in_round_with_killer(PEERS, killers)
	FixturePhotoModes.take(game, P1, FixturePhotoModes.dealt_film(game))
	FixturePhotoModes.use(game, P1, FixturePhotoModes.camera_of(game))
	var film := FixturePhotoModes.dealt_film(game)
	var camera := FixturePhotoModes.camera_of(game)
	# P2 lifts the film, then dies on the camera's spot: the film drops back exactly where and as
	# it lay, only the move serial differs.
	FixturePhotoModes.take(game, P2, film)
	assert_object(Items.held_by(game.state, P2)).is_same(film)
	FixtureItemModes.stand(game, P2, FixturePhotoModes.CAMERA_AT)
	var lifted_moves := film.moves
	killers[0].queues = [P2]
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DEAD)
	assert_int(film.where).is_equal(ItemState.Where.GROUND)
	assert_vector(film.position).is_equal(FixturePhotoModes.CAMERA_AT)
	assert_int(film.moves).is_greater(lifted_moves)
	# The next Interact with a fresh film is a load, not a shot.
	var fresh := FixturePhotoModes.give_film(game, P3)
	FixturePhotoModes.use(game, P3, camera)
	assert_int(_shots(game)).is_equal(0)
	assert_array(FixturePhotoModes.reasons(game, P3)).is_empty()
	assert_array(FixturePhotoModes.received(game, P3, &"FilmLoaded")).has_size(2)
	assert_object(FixturePhotoModes.state_of(game).loaded).is_same(fresh)


func test_a_vanished_film_whose_id_returns_on_the_camera_is_not_loaded() -> void:
	var game := _loaded()
	var film := FixturePhotoModes.dealt_film(game)
	var id := film.id
	game.state.remove_item(id)
	game.state.skip_item_ids_to(MatchState.MAX_ITEM_ID + 1)
	var twin := FixtureItemModes.lay(game, &"film", FixturePhotoModes.CAMERA_AT)
	assert_int(twin.id).is_equal(id)
	twin.moves = film.moves
	FixturePhotoModes.use(game, P3, FixturePhotoModes.camera_of(game))
	assert_array(FixturePhotoModes.reasons(game, P3)).is_equal([&"no_film"])
	assert_int(_shots(game)).is_equal(0)


func test_the_refusal_order_puts_the_station_conditions_first() -> void:
	var game := _round()
	var camera := FixturePhotoModes.camera_of(game)
	FixturePhotoModes.take(game, P1, FixtureItemModes.lay(game, &"package", Vector3(20, 0, 0)))
	FixturePhotoModes.use(game, P1, camera)
	FixtureItemModes.stand(game, P2, FixturePhotoModes.CAMERA_AT + Vector3(0, 0, -5))
	FixtureStationModes.interact(game, P2, camera)
	assert_array(FixturePhotoModes.reasons(game, P1)).is_equal([&"two_handed"])
	assert_array(FixturePhotoModes.reasons(game, P2)).is_equal([&"out_of_reach"])


func test_an_actor_failing_two_station_conditions_gets_the_first_reason() -> void:
	var game := _round()
	var camera := FixturePhotoModes.camera_of(game)
	FixturePhotoModes.take(game, P1, FixtureItemModes.lay(game, &"package", Vector3(20, 0, 0)))
	# Two-handed and out of reach at once: HandNotTwoHanded is the rule's first condition.
	FixtureItemModes.stand(game, P1, FixturePhotoModes.CAMERA_AT + Vector3(0, 0, -5))
	FixtureStationModes.interact(game, P1, camera)
	assert_array(FixturePhotoModes.reasons(game, P1)).is_equal([&"two_handed"])


func test_a_wall_between_the_actor_and_the_camera_refuses_blocked_before_any_film_reason() -> void:
	var wall := FlatWorldQuery.new().add_wall(AABB(Vector3(-1, 0, 19.7), Vector3(2, 3, 0.1)))
	var game := FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS, {}, wall)
	# Empty-handed with an empty camera would be no_film were it not for the wall.
	FixturePhotoModes.use(game, P1, FixturePhotoModes.camera_of(game))
	assert_array(FixturePhotoModes.reasons(game, P1)).is_equal([&"blocked"])
	assert_array(FixturePhotoModes.received(game, P1, &"FilmLoaded")).is_empty()


func test_the_photo_spot_takes_no_use() -> void:
	var game := _round()
	var task := FixturePhotoModes.task_of(game)
	var spot: StationState = game.state.stations[FixturePhotoModes.state_of(game).photo_spot]
	var ctx := MatchContext.new(game)
	ctx.actor = P1
	assert_str(task.type.use_problem(ctx, task, spot)).is_equal("unavailable")


func test_a_done_task_refuses_the_camera_unavailable() -> void:
	var game := _loaded()
	FixturePhotoModes.state_of(game).counted = PackedInt32Array([0, 1])
	FixturePhotoModes.use(game, P2, FixturePhotoModes.camera_of(game))
	assert_array(FixturePhotoModes.reasons(game, P2)).is_equal([&"unavailable"])
	assert_int(_shots(game)).is_equal(0)


func test_use_reasons_lists_the_six_reasons() -> void:
	var reasons := FixturePhotoModes.type_of(FixturePhotoModes.basic()).use_reasons()
	(
		assert_array(reasons)
		. contains_exactly_in_any_order(
			[
				&"unavailable",
				&"no_film",
				&"no_frames_left",
				&"film_exposed",
				&"nothing_to_print",
				&"no_photo",
			]
		)
	)
	for reason: StringName in reasons:
		assert_bool(StationUsable.REASONS.has(reason)).is_true()
