extends GdUnitTestSuite
## ToggleViews (#1295, ARCHITECTURE §4.7.61) on a fixture level read by the names LevelWorld reads
## (group `toggle_<key>`, metadata `toggle_index`, a mover's OnPose), fed only the events a client
## receives (StationPlaced, SwitchChanged) for FixtureToggles' mode: an open cover leaves layer 1
## and is hidden, so the voice's muffle ray (Muffle.blocked) and SightHider pass it; the
## bookcase's mover stands at its OnPose on layer 1, opened from the wine rack too (one key); the
## breaker (no key) moves nothing; every part stands as its scene again when the model or the level
## goes. Also: no toggle kind is drawn as a cylinder (CircleViews), a placed toggle is offered
## (StationUse), and only a StaticBody3D is a part, as on the host.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
## Station ids as the fixture's deal gives them: the covers in marker order, then book, bottle
## and breaker (FixtureToggles).
const COVER_0 := 1
const COVER_1 := 2
const BOOK := 3
const BOTTLE := 4
const BREAKER := 5
const ON_POSE := Vector3(2, 0, 0)

var _world: Node3D
var _level: Node3D
var _views: ToggleViews
var _cover_0: StaticBody3D
var _cover_1: StaticBody3D
var _mover: StaticBody3D


func before_test() -> void:
	_world = World.new()
	add_child(_world)
	_level = Node3D.new()
	_world.add_child(_level)
	_cover_0 = _part(&"cover", 0, Vector3(0, 1, 0))
	_cover_1 = _part(&"cover", 1, Vector3(0, 1, 10))
	_mover = _part(&"bookcase", 0, Vector3(10, 1, 0))
	var pose := Marker3D.new()
	pose.name = StationKind.ON_POSE
	pose.position = ON_POSE
	_mover.add_child(pose)
	_views = ToggleViews.new()
	_views.mode = FixtureToggles.mode()
	_world.add_child(_views)
	_views.level = _level


func after_test() -> void:
	_world.free()


func test_an_open_cover_leaves_layer_1_and_the_voice_ray_passes() -> void:
	_views.model = _dealt()
	await _frames()
	assert_int(_views.part_count()).is_equal(3)
	assert_bool(Muffle.blocked(_space(), Vector3(-3, 1, 0), Vector3(3, 1, 0))).is_true()
	_switch(COVER_0, true)
	await _frames()
	assert_int(_cover_0.collision_layer).is_equal(0)
	assert_bool(_cover_0.visible).is_false()
	assert_int(_cover_1.collision_layer).is_equal(PhysicsLayers.WORLD)
	assert_bool(_cover_1.visible).is_true()
	assert_bool(Muffle.blocked(_space(), Vector3(-3, 1, 0), Vector3(3, 1, 0))).is_false()
	assert_bool(SightHider.sees(_space(), Vector3(-3, 1, 10), Vector3(3, 1, 10))).is_false()
	_switch(COVER_0, false)
	await _frames()
	assert_int(_cover_0.collision_layer).is_equal(PhysicsLayers.WORLD)
	assert_bool(_cover_0.visible).is_true()
	assert_bool(Muffle.blocked(_space(), Vector3(-3, 1, 0), Vector3(3, 1, 0))).is_true()


func test_the_second_cover_station_opens_the_second_cover() -> void:
	_views.model = _dealt()
	_switch(COVER_1, true)
	await _frames()
	assert_int(_cover_0.collision_layer).is_equal(PhysicsLayers.WORLD)
	assert_int(_cover_1.collision_layer).is_equal(0)


func test_the_bookcase_stands_at_its_on_pose_from_either_station() -> void:
	_views.model = _dealt()
	var rest := _mover.transform
	# The host flips every station of one toggle together: the wine rack opens the bookcase too.
	_switch(BOOK, true)
	_switch(BOTTLE, true)
	await _frames()
	assert_vector(_mover.position).is_equal_approx(Vector3(12, 1, 0), Vector3.ONE * 1e-4)
	assert_int(_mover.collision_layer).is_equal(PhysicsLayers.WORLD)
	assert_bool(SightHider.sees(_space(), Vector3(10, 1, -3), Vector3(10, 1, 3))).is_true()
	assert_bool(SightHider.sees(_space(), Vector3(12, 1, -3), Vector3(12, 1, 3))).is_false()
	_switch(BOOK, false)
	_switch(BOTTLE, false)
	await _frames()
	assert_bool(_mover.transform.is_equal_approx(rest)).is_true()


func test_the_breaker_has_no_part_and_moves_nothing() -> void:
	_views.model = _dealt()
	_switch(BREAKER, true)
	await _frames()
	assert_dict(ToggleViews.open_toggles(_views.model, _views.mode)).is_empty()
	assert_int(_cover_0.collision_layer).is_equal(PhysicsLayers.WORLD)
	assert_vector(_mover.position).is_equal(Vector3(10, 1, 0))


func test_parts_stand_as_their_scene_once_the_model_or_the_level_goes() -> void:
	_views.model = _dealt()
	_switch(COVER_0, true)
	_switch(BOOK, true)
	await _frames()
	_views.model = null
	assert_int(_cover_0.collision_layer).is_equal(PhysicsLayers.WORLD)
	assert_vector(_mover.position).is_equal(Vector3(10, 1, 0))
	_views.model = _dealt()
	_switch(COVER_0, true)
	await _frames()
	assert_int(_cover_0.collision_layer).is_equal(0)
	_views.level = null
	assert_int(_cover_0.collision_layer).is_equal(PhysicsLayers.WORLD)
	assert_bool(_cover_0.visible).is_true()
	assert_int(_views.part_count()).is_equal(0)


func test_no_toggle_kind_is_drawn_as_a_cylinder() -> void:
	var made := FixtureToggles.mode()
	for id: StringName in [&"cover", &"book", &"bottle", &"breaker"]:
		assert_bool(CircleViews.draws(made, id)).override_failure_message(id).is_false()
	# A kind no task type holds and no PlaceToggles places keeps the fallback cylinder.
	assert_bool(CircleViews.draws(made, &"elsewhere")).is_true()


func test_a_placed_toggle_is_offered() -> void:
	var model := _dealt()
	for id: int in [COVER_0, BOOK, BREAKER]:
		assert_bool(StationUse.usable(model, _views.mode, id)).is_true()


# A model of FixtureToggles' mode in its round with the deal's toggle stations placed.
func _dealt() -> ClientModel:
	var model := ClientModel.new(_views.mode)
	model.own_peer = FixtureToggles.P1
	_fold(model, PhaseChangedEvent.new(&"round", 1000))
	var placed: Array[Array] = [
		[COVER_0, &"cover"],
		[COVER_1, &"cover"],
		[BOOK, &"book"],
		[BOTTLE, &"bottle"],
		[BREAKER, &"breaker"],
	]
	for row: Array in placed:
		_fold(
			model,
			StationPlacedEvent.new(row[0] as int, row[1] as StringName, Color.WHITE, Vector3.ZERO)
		)
	return model


func _switch(id: int, on: bool) -> void:
	_fold(_views.model, SwitchChangedEvent.new(id, on))


func _fold(model: ClientModel, event: MatchEvent) -> void:
	model.fold(event.event_name(), event.to_dict())


func _space() -> PhysicsDirectSpaceState3D:
	return _world.get_world_3d().direct_space_state


func _part(key: StringName, index: int, center: Vector3) -> StaticBody3D:
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.position = center
	body.add_to_group(StringName(StationKind.TOGGLE_GROUP_PREFIX + key), true)
	body.set_meta(StationKind.TOGGLE_INDEX_META, index)
	_level.add_child(body)
	return body


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
