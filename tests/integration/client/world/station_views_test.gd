extends GdUnitTestSuite
## StationViews (#801, ARCHITECTURE §4.7.54) on the real station scenes (`levels/stations/`) under
## a fixture level, fed only the events a client receives (FixtureGeneratorClient): the switches'
## on and off parts, the fixed look of a scene no station binds (GE14), the generator's bars from
## the fixed count up and its glow (GD4), the button's press, one wrapper per scene across deals,
## the wrappers hidden from a downed eye behind a wall (render checklist item 3), and no material
## drawn through walls.

const G := preload("res://tests/fixtures/client/fixture_generator_client.gd")
const World := preload("res://tests/integration/client/player/player_test_world.gd")
const SWITCH_SCENE := preload("res://levels/stations/switch.tscn")
const GENERATOR_SCENE := preload("res://levels/stations/generator.tscn")
## The use spots' offsets from the scenes' floor points (the scenes' UseSpot).
const SWITCH_SPOT := Vector3(0, 0, 1.4)
const GENERATOR_SPOT := Vector3(0, 0, 1.2)

var _world: Node3D
var _level: Node3D
var _views: StationViews


func before_test() -> void:
	_world = World.new()
	add_child(_world)
	_level = Node3D.new()
	_world.add_child(_level)
	var generator := GENERATOR_SCENE.instantiate() as Node3D
	generator.position = FixtureGeneratorModes.GENERATOR_AT - GENERATOR_SPOT
	_level.add_child(generator)
	for spot: Vector3 in FixtureGeneratorModes.SWITCH_SPOTS:
		var switch := SWITCH_SCENE.instantiate() as Node3D
		switch.position = spot - SWITCH_SPOT
		_level.add_child(switch)
	_views = StationViews.new()
	_views.mode = FixtureGeneratorModes.basic()
	_world.add_child(_views)
	_views.level = _level


func after_test() -> void:
	_world.free()


func test_not_dealt_every_scene_keeps_its_default_look() -> void:
	_views.model = ClientModel.new(_views.mode)
	await _frames()
	for i in FixtureGeneratorModes.SWITCHES:
		assert_bool(_switch_part(i, "Fixed").visible).is_false()
		assert_bool(_switch_part(i, "StationSight/Active/Off").visible).is_true()
	assert_int(_bars_lit()).is_equal(0)
	assert_bool(_generator_part("StationSight/Glow").visible).is_false()


func test_bound_switches_follow_switch_changed_and_light_the_bars() -> void:
	_views.model = G.dealt()
	await _frames()
	assert_int(_bars_lit()).is_equal(0)
	G.switch_to(_views.model, 1, true)
	await _frames()
	assert_bool(_switch_part(1, "StationSight/Active/On").visible).is_true()
	assert_bool(_switch_part(1, "StationSight/Active/Off").visible).is_false()
	assert_bool(_switch_part(0, "StationSight/Active/On").visible).is_false()
	assert_int(_bars_lit()).is_equal(1)
	# Filled from one end: the first bar, whichever switch it was.
	assert_bool(_generator_part("StationSight/Bars/Bar1").visible).is_true()
	for i in FixtureGeneratorModes.SWITCHES:
		assert_int(_views.station_of_body(_switch_part(i, "Collision"))).is_equal(
			G.FIRST_SWITCH + i
		)


func test_a_scene_no_station_binds_shows_the_fixed_look_and_is_no_target() -> void:
	# Three active switches: the fourth scene is a fixed switch, its bar lit from the start.
	_views.model = G.dealt(3)
	await _frames()
	assert_bool(_switch_part(3, "Fixed").visible).is_true()
	assert_bool(_switch_part(3, "StationSight/Active").visible).is_false()
	assert_int(_views.station_of_body(_switch_part(3, "Collision"))).is_equal(-1)
	assert_bool(_switch_part(0, "Fixed").visible).is_false()
	assert_int(_bars_lit()).is_equal(1)


func test_the_glow_shows_once_every_bar_is_lit() -> void:
	_views.model = G.dealt(3)
	for i in 3:
		G.switch_to(_views.model, i, true)
	await _frames()
	assert_int(_bars_lit()).is_equal(FixtureGeneratorModes.SWITCHES)
	assert_bool(_generator_part("StationSight/Glow").visible).is_true()
	G.switch_to(_views.model, 0, false)
	await _frames()
	assert_bool(_generator_part("StationSight/Glow").visible).is_false()


func test_the_button_moves_in_at_each_press_and_back() -> void:
	_views.model = G.dealt()
	G.fold(_views.model, ButtonPressedEvent.new(G.GENERATOR))
	await _frames()
	var button := _generator_part("StationSight/Button")
	var rest := button.position
	# The press before the bind replays nothing.
	var fresh := GENERATOR_SCENE.instantiate()
	assert_vector(rest).is_equal_approx(
		(fresh.get_node(^"Button") as Node3D).position, Vector3.ONE * 0.0001
	)
	fresh.free()
	G.fold(_views.model, ButtonPressedEvent.new(G.GENERATOR))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(button.position.z).is_less(rest.z)
	await get_tree().create_timer(StationViews.PRESS_SECONDS * 2.0).timeout
	assert_vector(button.position).is_equal(rest)


func test_a_second_deal_binds_again_with_one_wrapper_per_scene() -> void:
	_views.model = G.dealt()
	await _frames()
	_views.model.clear_match()
	await _frames()
	_views.model = G.dealt(3)
	await _frames()
	for root: Node3D in _views.scene_roots():
		var wrappers := 0
		for child: Node in root.get_children():
			if child is StationViews.StationSight:
				wrappers += 1
		assert_int(wrappers).is_equal(1)
	assert_bool(_switch_part(3, "Fixed").visible).is_true()
	assert_object(_views.scene_of(G.FIRST_SWITCH)).is_same(_level.get_child(1))


func test_each_switch_binds_the_scene_on_its_spot_not_the_first_free_one() -> void:
	# The level's first two switch scenes swap places: the deal's order no longer follows the
	# scenes' order, as in a real deal, whose spots come in random order.
	var first := _level.get_child(1) as Node3D
	var second := _level.get_child(2) as Node3D
	var first_at := first.position
	first.position = second.position
	second.position = first_at
	_views.model = G.dealt()
	await _frames()
	assert_object(_views.scene_of(G.FIRST_SWITCH)).is_same(second)
	assert_object(_views.scene_of(G.FIRST_SWITCH + 1)).is_same(first)
	G.switch_to(_views.model, 0, true)
	await _frames()
	assert_bool((second.get_node(^"StationSight/Active/On") as Node3D).visible).is_true()
	assert_bool((first.get_node(^"StationSight/Active/On") as Node3D).visible).is_false()


func test_a_switch_beyond_the_tolerance_of_every_scene_binds_none() -> void:
	# The first switch scene stands far from every placed switch: no station binds it, so it
	# shows the fixed look, and the first switch station has no scene.
	var far := _level.get_child(1) as Node3D
	far.position += Vector3(10.0, 0.0, 0.0)
	_views.model = G.dealt()
	await _frames()
	assert_object(_views.scene_of(G.FIRST_SWITCH)).is_null()
	assert_bool((far.get_node(^"Fixed") as Node3D).visible).is_true()
	assert_int(_views.station_of_body(far.get_node(^"Collision"))).is_equal(-1)
	for i in range(1, FixtureGeneratorModes.SWITCHES):
		assert_object(_views.scene_of(G.FIRST_SWITCH + i)).is_same(_level.get_child(i + 1))


func test_a_downed_eye_behind_a_wall_sees_no_driven_part() -> void:
	_views.model = G.dealt()
	G.switch_to(_views.model, 0, true)
	await _frames()
	var sight := _switch_part(0, "StationSight")
	assert_bool(sight.is_in_group(SightHider.GROUP)).is_true()
	assert_bool(_generator_part("StationSight").is_in_group(SightHider.GROUP)).is_true()
	var spot: Vector3 = FixtureGeneratorModes.SWITCH_SPOTS[0]
	_world.call(&"add_box", spot + Vector3(0, 1.0, 2.0), Vector3(2.0, 2.0, 0.1))
	var hider := SightHider.new()
	_world.add_child(hider)
	hider.watch_from(spot + Vector3(0, 0.3, 3.0))
	await _frames()
	hider.hide_unseen()
	assert_bool(sight.visible).is_false()
	hider.watch_from(spot + Vector3(0, 0.3, 1.0))
	hider.hide_unseen()
	assert_bool(sight.visible).is_true()


func test_no_station_part_draws_through_walls() -> void:
	_views.model = G.dealt()
	await _frames()
	var meshes := 0
	for root: Node3D in _views.scene_roots():
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			meshes += 1
			for material: Material in _materials_of(mesh):
				var base := material as BaseMaterial3D
				if base != null:
					(
						assert_bool(base.no_depth_test)
						. override_failure_message(str(mesh.get_path()))
						. is_false()
					)
	assert_int(meshes).is_greater(0)


func _materials_of(mesh: MeshInstance3D) -> Array[Material]:
	var found: Array[Material] = []
	for material: Material in [mesh.material_override, mesh.material_overlay]:
		if material != null:
			found.append(material)
	if mesh.mesh != null:
		for i in mesh.mesh.get_surface_count():
			var surface := mesh.get_surface_override_material(i)
			if surface == null:
				surface = mesh.mesh.surface_get_material(i)
			if surface != null:
				found.append(surface)
	return found


## Switch scene `index` (level order) part at `path`.
func _switch_part(index: int, path: String) -> Node3D:
	return _level.get_child(index + 1).get_node(path) as Node3D


func _generator_part(path: String) -> Node3D:
	return _level.get_child(0).get_node(path) as Node3D


func _bars_lit() -> int:
	var lit := 0
	for i in FixtureGeneratorModes.SWITCHES:
		if _generator_part("StationSight/Bars/Bar%d" % (i + 1)).visible:
			lit += 1
	return lit


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
