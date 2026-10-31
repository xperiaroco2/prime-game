extends GdUnitTestSuite
## The ship's engine on the estate (#1462, part 3 of #1225; ARCHITECTURE §9.5.27): the ship
## (`levels/estate/rooms/ship.tscn`) carries every marker the base mode's engine reads, as part 2's
## contract asks (PR #1463, "For part 3"): one console, two gill buttons, two breaker boards with
## exactly four breakers nearest each, four cartridge sockets and two chargers, each a use spot on
## the deck in front of its device's point in docs/design/estate-map.md §5a, and the two corners of
## the aboard box, which holds every station and leaves the ground beside the ship out. The gill
## sets' stand-ins (five slits, their light bars and the button) stand by the gill buttons.

const HouseMarkers := preload("res://tests/integration/levels/house_markers_test.gd")
const MAP := "res://levels/estate/estate.tscn"
const SHIP := "res://levels/estate/rooms/ship.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## How far a marker may stand off the floor under it: float noise, no step.
const SPAWN_FLOOR_M := 0.02
## The devices' points in estate-map §5a ("Positions inside, as built"), from the ship's centre
## (x east, y south: the scene's +z). A breaker hangs on its board.
const DOC_POINTS: Dictionary[StringName, Array] = {
	&"engine_console": [Vector2(0.0, 0.6)],
	&"gill_button": [Vector2(-2.856, -3.433), Vector2(2.856, -3.433)],
	&"breaker_board": [Vector2(-6.664, -0.902), Vector2(6.664, -0.902)],
	&"breaker": [Vector2(-6.664, -0.902), Vector2(6.664, -0.902)],
	&"cartridge_socket":
	[
		Vector2(-1.8, 3.112),
		Vector2(1.8, 3.112),
		Vector2(-3.426, -2.358),
		Vector2(3.426, -2.358),
	],
	&"cartridge_charger": [Vector2(-10.269, 3.237), Vector2(10.269, 3.237)],
}
## The markers of each engine tag part 2 asks for (`add_demands`: exact, the chargers at least 1).
const COUNTS: Dictionary[StringName, int] = {
	&"engine_console": 1,
	&"gill_button": 2,
	&"breaker_board": 2,
	&"breaker": 8,
	&"cartridge_socket": 4,
	&"cartridge_charger": 2,
	&"engine_aboard": 2,
}
## How far a use spot may stand from its device's point: in front of its wall (a charger is 0.9 m
## deep) and, for a breaker, along its board.
const SPOT_REACH_M := 1.5
## The deck's height over the ship's origin (the ship stands on legs, §5a).
const DECK_M := 1.2


func test_the_ship_has_each_engine_marker_part_two_asks_for() -> void:
	var layout := _read().layout
	for tag: StringName in COUNTS:
		assert_int(layout.count(tag)).override_failure_message("the %s markers" % tag).is_equal(
			COUNTS[tag]
		)


func test_each_board_is_the_nearest_board_of_four_breakers() -> void:
	var layout := _read().layout
	var boards := layout.positions(&"breaker_board")
	var held: Array[int] = []
	held.resize(boards.size())
	held.fill(0)
	for at: Vector3 in layout.positions(&"breaker"):
		var nearest := 0
		for i in boards.size():
			if at.distance_to(boards[i]) < at.distance_to(boards[nearest]):
				nearest = i
		held[nearest] += 1
	assert_array(held).is_equal([4, 4])


func test_every_station_lies_inside_the_aboard_box_and_the_ground_beside_it_does_not() -> void:
	var layout := _read().layout
	var corners := layout.positions(&"engine_aboard")
	assert_int(corners.size()).is_equal(2)
	var low := corners[0].min(corners[1])
	var high := corners[0].max(corners[1])
	for tag: StringName in DOC_POINTS:
		for at: Vector3 in layout.positions(tag):
			(
				assert_bool(ShipEngine.in_box(at, low, high))
				. override_failure_message("the %s marker at %s is not aboard" % [tag, at])
				. is_true()
			)
	var ship := _ship_origin()
	# The ground under a wing and the ramp's foot (§5a: its foot at (0, -12.6)) are not aboard.
	assert_bool(ShipEngine.in_box(ship + Vector3(10.0, 0.0, -6.0), low, high)).is_false()
	assert_bool(ShipEngine.in_box(ship + Vector3(0.0, 0.0, -12.6), low, high)).is_false()
	assert_bool(ShipEngine.in_box(ship + Vector3(0.0, DECK_M, -0.4), low, high)).is_true()


func test_each_station_marker_stands_in_front_of_its_device_in_the_estate_map() -> void:
	var layout := _read().layout
	var ship := _ship_origin()
	for tag: StringName in DOC_POINTS:
		for at: Vector3 in layout.positions(tag):
			var local := Vector2(at.x - ship.x, at.z - ship.z)
			var nearest := INF
			for point: Vector2 in DOC_POINTS[tag]:
				nearest = minf(nearest, local.distance_to(point))
			(
				assert_float(nearest)
				. override_failure_message("the %s marker at %s (%s)" % [tag, at, local])
				. is_less_equal(SPOT_REACH_M)
			)


func test_each_station_marker_stands_a_player_on_the_deck_clear_of_the_level() -> void:
	var mode := load(BASE_MODE) as GameMode
	var rules := mode.player_rules
	var level := LevelWorld.build(MAP)
	var world := _world(level, rules)
	var layout := MarkerReader.read_scene(MAP, world, MarkerReader.floor_tags_of(mode)).layout
	var deck := _ship_origin().y + DECK_M
	for tag: StringName in DOC_POINTS:
		for at: Vector3 in layout.positions(tag):
			var where := "the %s marker at %s" % [tag, at]
			assert_float(absf(at.y - deck)).override_failure_message(where).is_less_equal(
				SPAWN_FLOOR_M
			)
			(
				assert_float(HouseMarkers._off_the_floor(world, at, rules))
				. override_failure_message(where + ": not on the floor under it")
				. is_less_equal(SPAWN_FLOOR_M)
			)
			(
				assert_int(HouseMarkers._standing_hits(level, at, rules))
				. override_failure_message(where + ": a standing player does not fit there")
				. is_equal(0)
			)


func test_each_gill_set_has_its_slits_lights_and_button_by_a_gill_button_marker() -> void:
	var root: Node3D = auto_free((load(SHIP) as PackedScene).instantiate())
	add_child(root)
	var sets := get_tree().get_nodes_in_group(&"engine_gills")
	assert_int(sets.size()).is_equal(2)
	var buttons := _read().layout.positions(&"gill_button")
	var origin := _ship_origin()
	for gills: Node in sets:
		for i in range(1, 6):
			assert_object(gills.get_node_or_null("Slit%d/Open" % i)).is_not_null()
			assert_object(gills.get_node_or_null("Slit%d/Shut" % i)).is_not_null()
			assert_object(gills.get_node_or_null("Light%d" % i)).is_not_null()
		var button := gills.get_node_or_null("Button") as Node3D
		assert_object(button).is_not_null()
		var nearest := INF
		for at: Vector3 in buttons:
			nearest = minf(nearest, (button.global_position + origin).distance_to(at))
		assert_float(nearest).override_failure_message(str(gills.name)).is_less(1.5)
	remove_child(root)


func _ship_origin() -> Vector3:
	var estate: Node3D = (load(MAP) as PackedScene).instantiate()
	var origin := (estate.get_node(^"Ship") as Node3D).position
	estate.free()
	return origin


func _world(level: LevelWorld, rules: PlayerRules) -> HostWorldQuery:
	var world := HostWorldQuery.new(rules.capsule_radius_m, rules.crouch_height_m)
	world.add_level(level)
	world.use_level(MAP)
	return world


func _read() -> MarkerReader.Read:
	var mode := load(BASE_MODE) as GameMode
	return MarkerReader.read_scene(
		MAP, _world(LevelWorld.build(MAP), mode.player_rules), MarkerReader.floor_tags_of(mode)
	)
