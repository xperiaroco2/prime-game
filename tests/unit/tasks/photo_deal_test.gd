extends GdUnitTestSuite
## The photo task's deal, its exact demands and its level fit check (the photo ADR §2.1, PE11,
## PE12, PD18; ARCHITECTURE §9.5): the five stations in the order camera, photo spot, film box,
## printer, board, StationPlaced for each in id order, then the dealt film's ItemSpawned; nothing
## at 0 photos; exactly one marker of each tag; a photo spot within reach of the camera refused at
## load. Fixture values only.

const MAP := FixtureModes.MAP
const PEERS: Array[int] = [1, 2]


func test_the_deal_places_the_five_stations_then_the_film() -> void:
	var game := FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS)
	var task_state := FixturePhotoModes.state_of(game)
	var placed := FixturePhotoModes.received(game, 1, &"StationPlaced")
	var kinds: Array[StringName] = []
	var ids: Array[int] = []
	for event: Dictionary in placed:
		kinds.append(event["kind"])
		ids.append(event["station"])
	assert_array(kinds).is_equal([&"camera", &"photo_spot", &"film_box", &"printer", &"board"])
	(
		assert_array(ids)
		. is_equal(
			[
				task_state.camera,
				task_state.photo_spot,
				task_state.film_box,
				task_state.printer,
				task_state.board,
			]
		)
	)
	assert_vector(placed[0]["position"]).is_equal(FixturePhotoModes.CAMERA_AT)
	assert_vector(placed[1]["position"]).is_equal(FixturePhotoModes.SPOT_AT)
	var film := FixturePhotoModes.dealt_film(game)
	assert_object(film).is_not_null()
	assert_vector(film.position).is_equal(FixturePhotoModes.FILM_AT)
	assert_array(FixturePhotoModes.received(game, 2, &"ItemSpawned")).is_equal(
		[{"item": film.id, "kind": &"film", "position": FixturePhotoModes.FILM_AT}]
	)
	assert_int(task_state.photos).is_equal(2)
	assert_int(task_state.total()).is_equal(2)
	assert_bool(task_state.is_done()).is_false()


func test_the_deal_order_is_stations_then_the_film() -> void:
	var game := FixturePhotoModes.in_round(FixturePhotoModes.basic(), PEERS)
	var names := FixtureGeneratorModes.stream(game, 1, [&"StationPlaced", &"ItemSpawned"])
	(
		assert_array(names)
		. is_equal(
			[
				&"StationPlaced",
				&"StationPlaced",
				&"StationPlaced",
				&"StationPlaced",
				&"StationPlaced",
				&"ItemSpawned",
			]
		)
	)


func test_zero_photos_deals_a_done_task_and_places_nothing() -> void:
	var game := FixturePhotoModes.in_round(FixturePhotoModes.basic(0), PEERS)
	var task := FixturePhotoModes.task_of(game)
	assert_object(task).is_not_null()
	assert_bool((task.state as PhotoTask.State).is_done()).is_true()
	assert_array(FixturePhotoModes.received(game, 1, &"StationPlaced")).is_empty()
	assert_object(FixturePhotoModes.dealt_film(game)).is_null()


func test_it_demands_each_marker_exactly_once() -> void:
	var mode := FixturePhotoModes.basic()
	var demands := Demands.new(mode)
	FixturePhotoModes.type_of(mode).add_demands({&"photos": 3}, 10, demands)
	(
		assert_dict(demands.markers)
		. is_equal(
			{
				&"camera": 1,
				&"photo_spot": 1,
				&"film_box": 1,
				&"printer": 1,
				&"board": 1,
				&"film": 1,
				&"photo": 1,
			}
		)
	)
	for tag: StringName in demands.markers:
		assert_bool(demands.exact.has(tag)).is_true()


func test_the_fixture_layout_passes_the_load_check() -> void:
	var mode := FixturePhotoModes.basic()
	assert_array(Array(LayoutCheck.run(mode, FixturePhotoModes.layouts()))).is_empty()


func test_a_second_film_marker_is_refused_at_load() -> void:
	var mode := FixturePhotoModes.basic()
	var found := FixturePhotoModes.layouts()
	found[MAP].add_marker(&"film", Vector3(-20, 0, 20))
	var refused := "\n".join(LayoutCheck.run(mode, found))
	assert_str(refused).contains("%s has 2 film marker(s)" % MAP)
	assert_str(refused).contains("needs exactly 1")


func test_a_photo_spot_within_reach_of_the_camera_is_refused_at_load() -> void:
	var mode := FixturePhotoModes.basic()
	var apart := 2.0 * FixturePhotoModes.RADIUS_M
	var at := FixturePhotoModes.CAMERA_AT + Vector3(apart, 0, 0)
	var refused := "\n".join(LayoutCheck.run(mode, FixturePhotoModes.layouts(at)))
	assert_str(refused).contains("photo_spot_near")
	var above := FixturePhotoModes.CAMERA_AT + Vector3(0, 3, 0)
	var refused_above := "\n".join(LayoutCheck.run(mode, FixturePhotoModes.layouts(above)))
	assert_str(refused_above).contains("photo_spot_near")
	var beyond := FixturePhotoModes.CAMERA_AT + Vector3(apart + 0.01, 0, 0)
	assert_array(Array(LayoutCheck.run(mode, FixturePhotoModes.layouts(beyond)))).is_empty()
	var match_refused := Match.new(mode, 7, FlatWorldQuery.new(), FixturePhotoModes.layouts(at))
	assert_str("\n".join(match_refused.refusals)).contains("photo_spot_near")


func test_the_layout_problem_is_a_host_text_with_the_needed_and_the_actual_distance() -> void:
	var mode := FixturePhotoModes.basic()
	var type := FixturePhotoModes.type_of(mode)
	var apart := 2.0 * FixturePhotoModes.RADIUS_M
	var at := FixturePhotoModes.CAMERA_AT + Vector3(1.234, 0, 0)
	var layout: LevelLayout = FixturePhotoModes.layouts(at)[MAP]
	var found := type.layout_problems(layout)
	assert_int(found.size()).is_equal(1)
	assert_int(type.most_layout_problems()).is_equal(1)
	assert_str(found[0].id).is_equal(HostText.PHOTO_SPOT_NEAR)
	assert_array(Array(found[0].ids)).is_equal(["photo_spot", "camera"])
	assert_int(found[0].numbers[&"need"]).is_equal(ceili(apart * 100.0))
	assert_int(found[0].numbers[&"have"]).is_equal(123)
	var far: LevelLayout = FixturePhotoModes.layouts()[MAP]
	assert_array(type.layout_problems(far)).is_empty()
