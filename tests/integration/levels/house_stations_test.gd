extends GdUnitTestSuite
## The House's Generator stations (#799, G4; the Generator ADR's GE11): the five basement rooms
## place the switch and generator scenes in place of the plain markers, and the host's marker
## reader finds their use spots, snapped to the floor in the host's collision world, at the
## points of docs/design/house-map.md §6 (its Generator rows), each in its room, with a player
## standing there clear of every wall and device. No other marker shares a use spot's (x, z), and
## the art's own copy of each device is gone from the room's dressing (the scene is the device).

const MAP := "res://levels/house/house.tscn"
const DOC := "res://docs/design/house-map.md"
const HouseStationRooms := preload("res://tests/integration/levels/house_station_rooms.gd")
const SWITCH := "res://levels/stations/switch.tscn"
const GENERATOR := "res://levels/stations/generator.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## The tags of the use spots (provisional, "not a decision").
const TAGS: Array[StringName] = [&"switch", &"generator"]
## Each room's stations: their node under `Stations` and the scene each instances.
const STATIONS := {
	"storage": {"SwitchA": SWITCH},
	"boiler_room": {"SwitchB": SWITCH},
	"pump_room": {"SwitchC": SWITCH},
	"switch_room": {"SwitchD": SWITCH},
	"generator_hall": {"Generator": GENERATOR},
}
## How far a snapped use spot may lie from its §6 point (float noise, no offset).
const NEAR := 0.01
## The capsule's bottom this far above the floor, so the floor under it is no hit.
const FLOOR_GAP_M := 0.05


func test_the_use_spots_read_without_errors_in_the_host_s_world() -> void:
	var read := _read(TAGS)
	assert_array(Array(read.errors)).is_empty()
	assert_int(read.layout.count(&"switch")).is_equal(4)
	assert_int(read.layout.count(&"generator")).is_equal(1)


func test_each_use_spot_stands_at_its_house_map_point() -> void:
	var points := _doc_points()
	# §6's five Generator rows: the generator and the switches A to D.
	assert_int(points.size()).is_equal(5)
	var layout := _read(TAGS).layout
	for point: Array in points:
		var tag: StringName = point[0]
		var at: Vector3 = point[1]
		var found := false
		for spot: Vector3 in layout.positions(tag):
			found = found or spot.distance_to(at) <= NEAR
		(
			assert_bool(found)
			. override_failure_message(
				"no %s use spot at %s; found %s" % [tag, at, layout.positions(tag)]
			)
			. is_true()
		)


func test_each_room_instances_its_station_scenes_and_no_art_copy_of_them() -> void:
	HouseStationRooms.check(self, STATIONS)


func test_a_player_on_each_use_spot_stands_clear_of_walls_and_devices() -> void:
	var level := LevelWorld.build(MAP)
	var world := _world(level)
	var read := MarkerReader.read_scene(MAP, world, TAGS)
	var spots := PackedVector3Array()
	for tag: StringName in TAGS:
		spots.append_array(read.layout.positions(tag))
	assert_int(spots.size()).is_equal(5)
	for at: Vector3 in spots:
		(
			assert_int(_hits(level, at))
			. override_failure_message("a player on the use spot at %s meets the level" % at)
			. is_equal(0)
		)
	# The check can fail: a player pressed into the switch room's north wall (plan y 16).
	var by_wall := world.floor_below(Vector3(45, -2.0, 16.05))
	assert_bool(by_wall != WorldQuery.NO_FLOOR).is_true()
	assert_int(_hits(level, by_wall)).is_greater(0)


func test_no_other_marker_shares_a_use_spot_s_x_and_z() -> void:
	var tags: Array[StringName] = []
	tags.assign(TAGS)
	for tag: StringName in MarkerReader.floor_tags_of(load(BASE_MODE) as GameMode):
		if not tags.has(tag):
			tags.append(tag)
	var layout := _read(tags).layout
	for tag: StringName in TAGS:
		for spot: Vector3 in layout.positions(tag):
			for other: StringName in layout.tags():
				if other == tag:
					continue
				for at: Vector3 in layout.positions(other):
					var apart := Vector2(spot.x - at.x, spot.z - at.z).length()
					(
						assert_float(apart)
						. override_failure_message(
							(
								"the %s marker at %s shares the %s use spot at %s"
								% [other, at, tag, spot]
							)
						)
						. is_greater(NEAR)
					)


## §6's Generator rows as [tag, world point]: plan (x, y) at level L is (x, L * 3.2, y).
func _doc_points() -> Array[Array]:
	var points: Array[Array] = []
	var row := RegEx.create_from_string(
		"^\\| Generator \\| (Generator|Switch [A-D]) \\| (-?\\d+) \\| (-?[\\d.]+), (-?[\\d.]+) \\|"
	)
	var inside := false
	for line in FileAccess.get_file_as_string(DOC).split("\n"):
		if line.begins_with("## "):
			inside = line.begins_with("## 6.")
			continue
		var m := row.search(line) if inside else null
		if m == null:
			continue
		var tag := &"generator" if m.get_string(1) == "Generator" else &"switch"
		var at := Vector3(
			float(m.get_string(3)), int(m.get_string(2)) * 3.2, float(m.get_string(4))
		)
		points.append([tag, at])
	return points


func _world(level: LevelWorld) -> HostWorldQuery:
	var world := HostWorldQuery.new()
	world.add_level(level)
	world.use_level(MAP)
	return world


func _read(floor_tags: Array[StringName]) -> MarkerReader.Read:
	return MarkerReader.read_scene(MAP, _world(LevelWorld.build(MAP)), floor_tags)


## How many shapes of the House's world a standing player's capsule (the base mode's
## PlayerRules) meets with its feet on the floor at `feet`.
static func _hits(level: LevelWorld, feet: Vector3) -> int:
	var rules := (load(BASE_MODE) as GameMode).player_rules
	var capsule := CapsuleShape3D.new()
	capsule.radius = rules.capsule_radius_m
	capsule.height = rules.capsule_height_m - FLOOR_GAP_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	var centre := feet + Vector3.UP * (FLOOR_GAP_M + capsule.height / 2.0)
	query.transform = Transform3D(Basis.IDENTITY, centre)
	return level.space_state().intersect_shape(query).size()
