extends GdUnitTestSuite
## The House's car repair stations (#809, R5; the car repair ADR's RE15, RE16 and RD2): the garage
## and storage instance the car, lift panel, parts shelf and part picture scenes in place of the
## plain markers and the art's copies, and the host's marker reader finds their use spots,
## snapped to the floor in the host's collision world, at docs/design/house-map.md §6's points
## (the car's under the car, on the garage floor, not the lift's frame: RE16's exception). The
## panel's use spot sees nothing of the space under the car from any eye height of the crouch
## band (RE15, behind the partition R5 built), its cylinder lies within the voice radius less
## 1 m of the car's use spot and outside the car's own cylinder (RD2), no other marker (a
## respawn, a spawn, an item) lies in the car's footprint, and a player stands clear on each
## use spot.

const MAP := "res://levels/house/house.tscn"
const DOC := "res://docs/design/house-map.md"
const HouseStationRooms := preload("res://tests/integration/levels/house_station_rooms.gd")
const STATIONS_DIR := "res://levels/stations/"
const BASE_MODE := "res://content/modes/base_mode.tres"
## The station kinds' tags, all floor markers (snapped); provisional, "not a decision".
const TAGS: Array[StringName] = [
	&"car", &"car_end", &"lift_panel", &"part_bin_1", &"part_bin_2", &"part_bin_3", &"part_picture"
]
## The use spots a player stands on (car_end only gives the car's axis).
const SPOTS: Array[StringName] = [
	&"car", &"lift_panel", &"part_bin_1", &"part_bin_2", &"part_bin_3", &"part_picture"
]
## Each room's stations: their node under `Stations` and the scene each instances.
const STATIONS := {
	"garage":
	{"CarLift": "car.tscn", "LiftPanel": "lift_panel.tscn", "PartPicture": "part_picture.tscn"},
	"storage": {"PartsShelf": "parts_shelf.tscn"},
}
## §6's Car repair rows by their first words, and the tag of the marker at each.
const ROWS := {
	"Car parts shelf": &"part_bin_2",
	"Car on the lift": &"car",
	"Lift control": &"lift_panel",
	"Picture of the needed part": &"part_picture",
}
## RD2's placeholders ("not a decision"): the footprint's half-width (its half-length is the use
## spot to car_end), the raised underside's height, the stations' radius, and the margin under
## the voice radius that the panel's whole cylinder keeps from the car's use spot.
const HALF_WIDTH_M := 1.0
const CLEARANCE_M := 1.4
const RADIUS_M := 1.5
const CAR_RADIUS_M := 0.9
const VOICE_MARGIN_M := 1.0
## RE15's grid: every 0.5 m along the box (with both ends); the eyes every 0.1 m.
const GRID_M := 0.5
const EYE_STEP_M := 0.1
## The grid's lowest points this far above the floor, so the floor itself never blocks a ray.
const FLOOR_LIFT_M := 0.05
## The rim points of the panel's cylinder the extra RE15 check looks from.
const RIM := 8
const NEAR := 0.01
## The capsule's bottom this far above the floor, so the floor under it is no hit.
const FLOOR_GAP_M := 0.05


func test_the_markers_read_without_errors_one_of_each() -> void:
	var read := _read()
	assert_array(Array(read.errors)).is_empty()
	for tag: StringName in TAGS:
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
		var what := "%s at %s, not at §6's %s" % [tag, found[0], at]
		assert_float(found[0].distance_to(at)).override_failure_message(what).is_less(NEAR)


func test_the_car_s_use_spot_lies_on_the_garage_floor_and_car_end_along_its_axis() -> void:
	# RE16's exception: the use spot under the car snaps to the floor, never to the lift's frame.
	var layout := _read().layout
	var car := layout.positions(&"car")[0]
	var end := layout.positions(&"car_end")[0]
	assert_float(car.y).is_equal_approx(0.0, NEAR)
	assert_float(end.y).is_equal_approx(0.0, NEAR)
	(
		assert_bool(end.is_equal_approx(car + Vector3(0, 0, -2.3)))
		. override_failure_message("car_end at %s" % end)
		. is_true()
	)


func test_each_room_instances_its_station_scenes_and_no_art_copy_of_them() -> void:
	HouseStationRooms.check(self, STATIONS, STATIONS_DIR)


func test_the_panel_s_use_spot_sees_nothing_under_the_car_from_the_crouch_band() -> void:
	var level := LevelWorld.build(MAP)
	var world := _world(level)
	var layout := MarkerReader.read_scene(MAP, world, TAGS).layout
	var rules := (load(BASE_MODE) as GameMode).player_rules
	var panel := layout.positions(&"lift_panel")[0]
	var grid := _box_grid(layout.positions(&"car")[0], layout.positions(&"car_end")[0])
	assert_int(grid.size()).is_greater(100)
	# From the use spot, and from each point of its cylinder's rim that sees the use spot: a
	# holder may stand anywhere in the cylinder that keeps the station in sight.
	var origins: Array[Vector3] = [panel]
	for turn: int in RIM:
		var rim := panel + Vector3.FORWARD.rotated(Vector3.UP, TAU * turn / RIM) * RADIUS_M
		var lifted := Vector3.UP * rules.crouch_eye_height_m
		# A point inside a wall is no place to stand (and a ray from inside a box misses it).
		if _hits(level, rim) == 0 and world.line_of_sight(rim + lifted, panel + lifted):
			origins.append(rim)
	assert_int(origins.size()).is_greater(1)
	var seen: Array[String] = []
	for origin: Vector3 in origins:
		for eye_y: float in _steps(rules.crouch_eye_height_m, rules.eye_height_m, EYE_STEP_M):
			var eye := origin + Vector3.UP * eye_y
			for point: Vector3 in grid:
				if world.line_of_sight(eye, point) and seen.size() < 5:
					seen.append("%s sees %s" % [eye, point])
	(
		assert_array(seen)
		. override_failure_message("the panel sees under the car: %s" % [seen])
		. is_empty()
	)
	# The check can fail: east of the partition, a crouched eye sees the space under the car
	# (past the lift's post, which stands at the car's middle).
	var east := Vector3(panel.x + 3.0, rules.crouch_eye_height_m, panel.z - 1.5)
	assert_bool(world.line_of_sight(east, layout.positions(&"car")[0] + Vector3.UP * 0.5)).is_true()


func test_the_panel_s_cylinder_lies_within_voice_range_and_out_of_the_car_s_reach() -> void:
	var layout := _read().layout
	var mode := load(BASE_MODE) as GameMode
	var voice := (mode.find_phase(&"round").voice_rule as RoundVoice).living_m
	var car := layout.positions(&"car")[0]
	var panel := layout.positions(&"lift_panel")[0]
	var apart := Vector2(panel.x - car.x, panel.z - car.z).length()
	# Every point of the panel's cylinder within the voice radius less the margin of the car's
	# use spot, and outside the car's own cylinder (one player cannot hold the lift and fit).
	assert_float(apart + RADIUS_M).is_less_equal(voice - VOICE_MARGIN_M)
	assert_float(apart - RADIUS_M).is_greater_equal(CAR_RADIUS_M)


func test_no_other_marker_lies_in_the_car_s_footprint() -> void:
	var read := _read()
	var car := read.layout.positions(&"car")[0]
	var end := read.layout.positions(&"car_end")[0]
	var inside: Array[String] = []
	for tag: StringName in read.layout.tags():
		if tag == &"car" or tag == &"car_end":
			continue
		for at: Vector3 in read.layout.positions(tag):
			if _in_footprint(at, car, end):
				inside.append("%s at %s" % [tag, at])
	assert_array(inside).override_failure_message("in the footprint: %s" % [inside]).is_empty()
	# The check can fail: a point beside the use spot lies in it, one 1.5 m to its side not.
	assert_bool(_in_footprint(car + Vector3(0.5, 0, -1.0), car, end)).is_true()
	assert_bool(_in_footprint(car + Vector3(1.5, 0, 0), car, end)).is_false()


func test_a_player_on_each_use_spot_stands_clear_of_walls_and_devices() -> void:
	var level := LevelWorld.build(MAP)
	var read := MarkerReader.read_scene(MAP, _world(level), TAGS)
	for tag: StringName in SPOTS:
		for at: Vector3 in read.layout.positions(tag):
			(
				assert_int(_hits(level, at))
				. override_failure_message(
					"a player on the %s use spot at %s meets the level" % [tag, at]
				)
				. is_equal(0)
			)
	# The check can fail: a player inside the parts shelf.
	var bin := read.layout.positions(&"part_bin_2")[0]
	assert_int(_hits(level, bin + Vector3(0, 0, 1.65))).is_greater(0)


## Points of the space under the car: across its footprint (the use spot to car_end and as far
## back, HALF_WIDTH_M to each side), from the floor up to CLEARANCE_M, every GRID_M with both ends.
func _box_grid(car: Vector3, end: Vector3) -> Array[Vector3]:
	var along := end - car
	var half_length := along.length()
	along = along.normalized()
	var side := along.cross(Vector3.UP)
	var points: Array[Vector3] = []
	for a: float in _steps(-half_length, half_length, GRID_M):
		for w: float in _steps(-HALF_WIDTH_M, HALF_WIDTH_M, GRID_M):
			for h: float in _steps(FLOOR_LIFT_M, CLEARANCE_M, GRID_M):
				points.append(car + along * a + side * w + Vector3.UP * h)
	return points


## From `from` to `to` every `step`, with both ends.
static func _steps(from: float, to: float, step: float) -> Array[float]:
	var values: Array[float] = []
	var at := from
	while at < to - 1e-4:
		values.append(at)
		at += step
	values.append(to)
	return values


## Whether `at` lies in the car's footprint box (RE7) on the car's floor.
static func _in_footprint(at: Vector3, car: Vector3, end: Vector3) -> bool:
	var along := end - car
	var half_length := along.length()
	along = along.normalized()
	var offset := at - car
	if offset.y < -0.5 or offset.y > CLEARANCE_M:
		return false
	var flat := Vector3(offset.x, 0, offset.z)
	var a := flat.dot(along)
	var w := flat.dot(along.cross(Vector3.UP))
	return absf(a) <= half_length and absf(w) <= HALF_WIDTH_M


## §6's Car repair rows as [tag, world point]: plan (x, y) at level L is (x, L * 3.2, y).
func _doc_points() -> Array[Array]:
	var points: Array[Array] = []
	var row := RegEx.create_from_string(
		"^\\| Car repair \\| ([^|]+?) \\| (-?\\d+) \\| (-?[\\d.]+), (-?[\\d.]+) \\|"
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
	return MarkerReader.read_scene(MAP, _world(LevelWorld.build(MAP)), TAGS)


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
