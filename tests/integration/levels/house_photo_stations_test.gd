extends GdUnitTestSuite
## The House's photo stations (#783, P4; the photo task ADR §9): the photo zone, the study, the
## darkroom and storage place the photo station scenes in place of the plain markers, and the
## host's marker reader finds their use spots, snapped to the floor in the host's collision world,
## at the points of docs/design/house-map.md §6 (its Photo rows), with a player standing on each
## device's use spot clear of every wall and device, the floor whole around it. The photo spot's
## whole mark lies beyond the camera's reach (PD18, PE12), the shooter sees a subject on it, the
## first film lies beside the camera, no other marker shares a photo marker's (x, z), and the art's
## own copy of each device is gone from the room's dressing (the scene is the device).

const MAP := "res://levels/house/house.tscn"
const DOC := "res://docs/design/house-map.md"
const HouseStationRooms := preload("res://tests/integration/levels/house_station_rooms.gd")
const STATIONS_DIR := "res://levels/stations/"
const BASE_MODE := "res://content/modes/base_mode.tres"
## The station kinds' tags, read as floor markers (snapped), and the items' (read as placed):
## provisional, "not a decision".
const STATION_TAGS: Array[StringName] = [
	&"camera", &"photo_spot", &"film_box", &"printer", &"photo_board"
]
const ITEM_TAGS: Array[StringName] = [&"film", &"photo"]
## The devices a player stands at (the photo spot is a floor mark: the subject stands on it).
const DEVICE_TAGS: Array[StringName] = [&"camera", &"film_box", &"printer", &"photo_board"]
## Each room's stations: their node under `Stations` and the scene each instances.
const STATIONS := {
	"photo_zone": {"PhotoSpot": "photo_spot.tscn", "Camera": "camera.tscn"},
	"storage": {"FilmBox": "film_box.tscn"},
	"study": {"Printer": "printer.tscn"},
	"darkroom": {"PhotoBoard": "photo_board.tscn"},
}
## §6's Photo rows by their first words, and the tag of the marker at each.
const ROWS := {
	"Photo spot": &"photo_spot",
	"Camera": &"camera",
	"A film": &"film",
	"Computer and printer": &"printer",
	"Board": &"photo_board",
	"Box of new films": &"film_box",
}
## The camera's and the photo spot's radius_m: PD9's placeholder, 2 m each ("not a decision").
const RADIUS_M := 2.0
## The pick-up's reach: the first film within it of the shooter's spot.
const REACH_M := 2.0
## How far a snapped marker may lie from its §6 point across the floor (float noise), and above
## its level's height (the gazebo's deck stands 0.15 m above the plot).
const NEAR := 0.01
const DECK_M := 0.2
## The capsule's bottom this far above the floor, so the floor under it is no hit.
const FLOOR_GAP_M := 0.05
## The floor probes around each use spot: this many, this far out (a player's step around it).
const AROUND := 8
const AROUND_M := 1.0


func test_the_markers_read_without_errors_one_of_each() -> void:
	var read := _read()
	assert_array(Array(read.errors)).is_empty()
	for tag: StringName in STATION_TAGS + ITEM_TAGS:
		assert_int(read.layout.count(tag)).override_failure_message(String(tag)).is_equal(1)


func test_each_marker_stands_at_its_house_map_point() -> void:
	var points := _doc_points()
	assert_int(points.size()).is_equal(ROWS.size())
	var layout := _read().layout
	for point: Array in points:
		var tag: StringName = point[0]
		var at: Vector3 = point[1]
		var found := layout.positions(tag)
		assert_int(found.size()).override_failure_message(String(tag)).is_equal(1)
		if found.size() != 1:
			continue
		var spot := found[0]
		var what := "%s at %s, not at §6's %s" % [tag, spot, at]
		var apart := Vector2(spot.x - at.x, spot.z - at.z).length()
		assert_float(apart).override_failure_message(what).is_less(NEAR)
		assert_float(spot.y - at.y).override_failure_message(what).is_between(-NEAR, DECK_M)


func test_each_room_instances_its_station_scenes_and_no_art_copy_of_them() -> void:
	HouseStationRooms.check(self, STATIONS, STATIONS_DIR)


func test_a_player_on_each_device_s_use_spot_stands_clear_of_walls_and_devices() -> void:
	var level := LevelWorld.build(MAP)
	var read := MarkerReader.read_scene(MAP, _world(level), STATION_TAGS)
	for tag: StringName in DEVICE_TAGS:
		for at: Vector3 in read.layout.positions(tag):
			(
				assert_int(_hits(level, at))
				. override_failure_message(
					"a player on the %s use spot at %s meets the level" % [tag, at]
				)
				. is_equal(0)
			)
	# The check can fail: a player in the study's art desk, where the printer's marker stood.
	assert_int(_hits(level, Vector3(40, 3.2, 29))).is_greater(0)


func test_the_floor_holds_around_each_device_s_use_spot() -> void:
	# A text edit of an art room once moved a floor tile beside the darkroom's board: a body
	# knocked there fell through the House.
	var level := LevelWorld.build(MAP)
	var world := _world(level)
	var read := MarkerReader.read_scene(MAP, world, STATION_TAGS)
	for tag: StringName in DEVICE_TAGS:
		for at: Vector3 in read.layout.positions(tag):
			for turn: int in AROUND:
				var probe := (
					at + Vector3.FORWARD.rotated(Vector3.UP, TAU * turn / AROUND) * AROUND_M
				)
				var floor_at := world.floor_below(probe + Vector3.UP * 0.1)
				var what := "no floor at %s beside the %s use spot at %s" % [probe, tag, at]
				(
					assert_bool(floor_at != WorldQuery.NO_FLOOR)
					. override_failure_message(what)
					. is_true()
				)
				(
					assert_float(absf(floor_at.y - at.y))
					. override_failure_message("%s: it lies at %s" % [what, floor_at])
					. is_less(DECK_M)
				)


func test_the_whole_photo_spot_lies_beyond_the_camera_s_reach() -> void:
	var layout := _read().layout
	var camera := layout.positions(&"camera")[0]
	var spot := layout.positions(&"photo_spot")[0]
	# PhotoTask.layout_problems refuses the spot no farther than the two radii (PE12).
	var apart := Vector2(spot.x - camera.x, spot.z - camera.z).length()
	assert_float(apart).is_greater(RADIUS_M + RADIUS_M)


func test_the_shooter_sees_a_subject_on_the_mark_and_not_through_the_backdrop() -> void:
	var level := LevelWorld.build(MAP)
	var world := _world(level)
	var layout := MarkerReader.read_scene(MAP, world, STATION_TAGS).layout
	var eye := (load(BASE_MODE) as GameMode).player_rules.eye_height_m
	var camera := layout.positions(&"camera")[0]
	var spot := layout.positions(&"photo_spot")[0]
	var lens := camera + Vector3.UP * eye
	var towards := Vector3(camera.x - spot.x, 0, camera.z - spot.z).normalized()
	# A subject on the mark's near half: across, near, far edge. (The art's pose screen and tripod
	# are gone from outdoor.tscn, #1066; the frame's aim has its own test below.)
	var side := towards.cross(Vector3.UP)
	for at: Vector3 in [
		spot + towards * 0.6,
		spot + towards * 0.6 + side * 1.0,
		spot + towards * 0.6 - side * 1.0,
		spot + towards * 1.6,
	]:
		var head := at + Vector3.UP * eye
		(
			assert_bool(world.line_of_sight(lens, head))
			. override_failure_message("the shooter at %s does not see a head at %s" % [lens, head])
			. is_true()
		)
	# The check can fail: 2 m beyond the mark's centre, behind the art's pose screen and its backdrop.
	var hidden := spot - towards * 2.0 + Vector3.UP * eye
	assert_bool(world.line_of_sight(lens, hidden)).is_false()


func test_the_lens_has_a_clear_line_to_the_aim_point() -> void:
	# The frame's aim is the spot raised by the eye height, its lens the camera's (photo task ADR
	# PE3, PhotoTask); the art's pose screen and tripod once stood on that line (#1066).
	var level := LevelWorld.build(MAP)
	var world := _world(level)
	var layout := MarkerReader.read_scene(MAP, world, STATION_TAGS).layout
	var eye := (load(BASE_MODE) as GameMode).player_rules.eye_height_m
	var lens := layout.positions(&"camera")[0] + Vector3.UP * eye
	var aim := layout.positions(&"photo_spot")[0] + Vector3.UP * eye
	(
		assert_bool(world.line_of_sight(lens, aim))
		. override_failure_message(
			"a level collider stands between the lens %s and the aim %s" % [lens, aim]
		)
		. is_true()
	)
	# The check can fail: the same line from the far side of the backdrop meets it.
	var towards := (lens - aim) * Vector3(1, 0, 1)
	assert_bool(world.line_of_sight(aim - towards.normalized() * 2.0, lens)).is_false()


func test_the_first_film_lies_on_the_floor_beside_the_camera() -> void:
	var level := LevelWorld.build(MAP)
	var world := _world(level)
	var layout := MarkerReader.read_scene(MAP, world, STATION_TAGS).layout
	var camera := layout.positions(&"camera")[0]
	var film := layout.positions(&"film")[0]
	assert_float(Vector2(film.x - camera.x, film.z - camera.z).length()).is_less(REACH_M)
	var floor_at := world.floor_below(film + Vector3.UP * 0.1)
	assert_bool(floor_at != WorldQuery.NO_FLOOR).is_true()
	assert_float(absf(film.y - floor_at.y)).is_less(0.05)


func test_no_other_marker_shares_a_photo_marker_s_x_and_z() -> void:
	var layout := _read().layout
	for tag: StringName in STATION_TAGS + ITEM_TAGS:
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
								"the %s marker at %s shares the %s marker at %s"
								% [other, at, tag, spot]
							)
						)
						. is_greater(NEAR)
					)


## §6's Photo rows as [tag, world point]: plan (x, y) at level L is (x, L * 3.2, y).
func _doc_points() -> Array[Array]:
	var points: Array[Array] = []
	var row := RegEx.create_from_string(
		"^\\| Photo \\| ([^|]+?) \\| (-?\\d+) \\| (-?[\\d.]+), (-?[\\d.]+) \\|"
	)
	var inside := false
	for line in FileAccess.get_file_as_string(DOC).split("\n"):
		if line.begins_with("## "):
			inside = line.begins_with("## 6.")
			continue
		var m := row.search(line) if inside else null
		if m == null:
			continue
		for words: String in ROWS:
			if m.get_string(1).begins_with(words):
				var at := Vector3(
					float(m.get_string(3)), int(m.get_string(2)) * 3.2, float(m.get_string(4))
				)
				points.append([ROWS[words], at])
	return points


func _world(level: LevelWorld) -> HostWorldQuery:
	var world := HostWorldQuery.new()
	world.add_level(level)
	world.use_level(MAP)
	return world


func _read() -> MarkerReader.Read:
	return MarkerReader.read_scene(MAP, _world(LevelWorld.build(MAP)), STATION_TAGS)


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
