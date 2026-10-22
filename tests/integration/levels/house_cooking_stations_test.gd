extends GdUnitTestSuite
## The House's cooking stations (#774, C5; the cooking ADR's CE15, CD1, CD15): the kitchen, storage,
## the chill zone and the greenhouse place the cooking station scenes in place of the plain markers
## `OrderBoard`, `Buns`, `Meat`, `Grill`, `HerbBoard` and `HerbBeds`, and the host's marker reader
## finds the order board, the three places, the grill, the herb board and the five beds (snapped to
## the floor in the host's collision world) and the six box markers (read as placed) at the points
## of docs/design/house-map.md §6 (its Burgers rows). The places are numbered 1 to 3 in level order
## (the order i on place i, CE8); a player on each used device's spot stands clear of every wall and
## device with the floor whole around it; each box lies on storage's floor; no other marker shares
## a cooking marker's (x, z); the art's own copy of each device is gone (the scene is the device);
## and no other map holds a cooking marker (CD15: none on the greybox).

const MAP := "res://levels/house/house.tscn"
const DOC := "res://docs/design/house-map.md"
const ROOMS := "res://levels/house/rooms/"
const HouseStationRooms := preload("res://tests/integration/levels/house_station_rooms.gd")
const OUTDOOR := "res://levels/house/outdoor.tscn"
const STATIONS_DIR := "res://levels/stations/"
const BASE_MODE := "res://content/modes/base_mode.tres"
const COOKING := "res://content/tasks/cooking.tres"
## The maps besides House (CD15: no cooking marker there).
const OTHER_MAPS: Array[String] = [
	"res://levels/greybox/greybox.tscn", "res://levels/lobby/lobby.tscn"
]
## The art's grill on the plot, which the chill zone's grill scene replaces.
const ART_GRILL := "res://levels/kit/house_props/bbq_grill.tscn"
## The station kinds' tags, read as floor markers (snapped), and the boxes' (items, read as
## placed): provisional, "not a decision".
const STATION_TAGS: Array[StringName] = [
	&"order_board", &"herb_board", &"grill", &"place", &"herb_bed"
]
const BOX_TAGS: Array[StringName] = [
	&"box_bun_white",
	&"box_bun_sesame",
	&"box_bun_dark",
	&"box_patty_light",
	&"box_patty_red",
	&"box_patty_deep_red",
]
## How many markers of each station tag: one board each, CD1's three places, five beds.
const COUNTS := {&"order_board": 1, &"herb_board": 1, &"grill": 1, &"place": 3, &"herb_bed": 5}
## The devices a player uses where they stand (the herb board is a display kind, CE6: nobody uses
## it; the order board hangs on a wall and is used from in front of it, see its own test).
const USED_TAGS: Array[StringName] = [&"grill", &"place", &"herb_bed"]
## Each room's stations: their node under `Stations` and the scene each instances.
const STATIONS := {
	"kitchen":
	{
		"OrderBoard": "order_board.tscn",
		"Place1": "place.tscn",
		"Place2": "place.tscn",
		"Place3": "place.tscn",
	},
	"storage": {"Buns": "bun_shelf.tscn", "Meat": "freezer.tscn"},
	"chill_zone": {"Grill": "grill.tscn"},
	"greenhouse": {"HerbBoard": "herb_board.tscn", "HerbBeds": "herb_beds.tscn"},
}
## §6's Burgers rows by their first words, and the tag of a marker at each.
const ROWS := {
	"Order board": &"order_board",
	"Place 1": &"place",
	"Place 2": &"place",
	"Place 3": &"place",
	"Buns": &"box_bun_sesame",
	"Raw meat": &"box_patty_red",
	"Grill": &"grill",
	"Herb board": &"herb_board",
	"Herb beds": &"herb_bed",
}
## How far a marker may lie from its §6 point (float noise).
const NEAR := 0.01
## How far a floor may lie from a marker standing on it.
const FLOOR_M := 0.05
## The capsule's bottom this far above the floor, so the floor under it is no hit.
const FLOOR_GAP_M := 0.05
## The floor probes around each use spot: this many, this far out (a player's step around it).
const AROUND := 8
const AROUND_M := 1.0
## The order board's search grid (its spacing) and how far past its reach a walk-in path must lead.
const STEP_M := 0.25
const WALK_IN_M := 0.5
const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _level: LevelWorld
var _world: HostWorldQuery
var _read: MarkerReader.Read


func before() -> void:
	_level = LevelWorld.build(MAP)
	_world = HostWorldQuery.new()
	_world.add_level(_level)
	_world.use_level(MAP)
	_read = MarkerReader.read_scene(MAP, _world, STATION_TAGS)


func test_the_markers_read_without_errors_one_box_of_each_kind() -> void:
	assert_array(Array(_read.errors)).is_empty()
	for tag: StringName in COUNTS:
		var what := String(tag)
		assert_int(_read.layout.count(tag)).override_failure_message(what).is_equal(COUNTS[tag])
	for tag: StringName in BOX_TAGS:
		assert_int(_read.layout.count(tag)).override_failure_message(String(tag)).is_equal(1)


func test_each_marker_stands_at_its_house_map_point() -> void:
	var points := _doc_points()
	assert_int(points.size()).is_equal(ROWS.size())
	for point: Array in points:
		var tag: StringName = point[0]
		var at: Vector3 = point[1]
		var found := false
		for spot: Vector3 in _read.layout.positions(tag):
			found = found or spot.distance_to(at) <= NEAR
		(
			assert_bool(found)
			. override_failure_message(
				"no %s marker at §6's %s; found %s" % [tag, at, _read.layout.positions(tag)]
			)
			. is_true()
		)


func test_each_room_instances_its_station_scenes_and_no_art_copy_of_them() -> void:
	HouseStationRooms.check(self, STATIONS, STATIONS_DIR)
	# The art's grill stood on the plot, not in the chill zone's room scene.
	var plot := auto_free((load(OUTDOOR) as PackedScene).instantiate()) as Node
	for node: Node in plot.find_children("*", "", true, false):
		var what := "the plot still stands the art's grill at %s" % plot.get_path_to(node)
		assert_str(node.scene_file_path).override_failure_message(what).is_not_equal(ART_GRILL)


func test_the_places_are_numbered_1_to_3_in_level_order() -> void:
	var kitchen := auto_free((load(ROOMS + "kitchen.tscn") as PackedScene).instantiate()) as Node3D
	var places := _read.layout.positions(&"place")
	assert_int(places.size()).is_equal(3)
	var last := -1
	for i: int in range(1, 4):
		var place := kitchen.get_node("Stations/Place%d" % i) as Node3D
		# Level order is scene-tree order: the deal puts order i on the i-th place marker (CE8).
		assert_int(place.get_index()).is_greater(last)
		last = place.get_index()
		assert_str((place.get_node("Number") as Label3D).text).is_equal(str(i))
		# The kitchen stands at its origin (34, 0, 30); the i-th marker is this place's use spot,
		# in front of its counter (the places stand in a row along x).
		var at := places[i - 1]
		var what := "place %d's marker at %s" % [i, at]
		assert_float(at.x - 34.0).override_failure_message(what).is_equal_approx(
			place.position.x, NEAR
		)


func test_a_player_on_each_used_device_s_spot_stands_clear_of_walls_and_devices() -> void:
	for tag: StringName in USED_TAGS:
		for at: Vector3 in _read.layout.positions(tag):
			(
				assert_int(_hits(at))
				. override_failure_message(
					"a player on the %s use spot at %s meets the level" % [tag, at]
				)
				. is_equal(0)
			)
	# The check can fail: a player in the middle of the places' counters, where the art's island
	# and the old marker stood.
	assert_int(_hits(Vector3(39, 0, 37))).is_greater(0)


func test_the_floor_holds_around_each_used_device_s_spot() -> void:
	for tag: StringName in USED_TAGS:
		for at: Vector3 in _read.layout.positions(tag):
			for turn: int in AROUND:
				var probe := (
					at + Vector3.FORWARD.rotated(Vector3.UP, TAU * turn / AROUND) * AROUND_M
				)
				var floor_at := _world.floor_below(probe + Vector3.UP * 0.1)
				var what := "no floor at %s beside the %s use spot at %s" % [probe, tag, at]
				(
					assert_bool(floor_at != WorldQuery.NO_FLOOR)
					. override_failure_message(what)
					. is_true()
				)
				(
					assert_float(absf(floor_at.y - at.y))
					. override_failure_message("%s: it lies at %s" % [what, floor_at])
					. is_less(0.2)
				)


## A burger is served at the order board (#1101). Its marker (the old display board's read spot,
## between the board and the places' counters) is too tight for a standing player, so the test
## looks on a STEP_M grid around it: some spot inside its reach (AtStation: the kind's radius_m)
## holds a standing player clear of the level on its floor, sees the marker (StationInSight: eye
## to the lifted marker) and joins clear spots out past the reach, so a player walks up to it.
func test_a_player_can_walk_up_to_the_order_board_and_see_it() -> void:
	var eye := (load(BASE_MODE) as GameMode).player_rules.eye_height_of(false)
	var reach := (load(COOKING) as Cooking).order_board.radius_m
	var span := ceili((reach + WALK_IN_M) / STEP_M) + 1
	for at: Vector3 in _read.layout.positions(&"order_board"):
		var clear: Dictionary[Vector2i, bool] = {}
		var open: Array[Vector2i] = []
		for x: int in range(-span, span + 1):
			for z: int in range(-span, span + 1):
				var feet := at + Vector3(x, 0, z) * STEP_M
				var floor_at := _world.floor_below(feet + Vector3.UP * 0.1)
				var free := (
					floor_at != WorldQuery.NO_FLOOR
					and absf(floor_at.y - at.y) < FLOOR_M
					and _hits(feet) == 0
				)
				clear[Vector2i(x, z)] = free
				if not free or feet.distance_to(at) > reach:
					continue
				if _world.line_of_sight(feet + Vector3.UP * eye, Items.lifted(at)):
					open.append(Vector2i(x, z))
		var what := "the order board at %s" % at
		assert_int(open.size()).override_failure_message("no spot sees " + what).is_greater(0)
		var seen: Dictionary[Vector2i, bool] = {}
		var walks_in := false
		while not open.is_empty() and not walks_in:
			var cell: Vector2i = open.pop_back()
			seen[cell] = true
			walks_in = Vector2(cell).length() * STEP_M > reach + WALK_IN_M
			for step: Vector2i in STEPS:
				if clear.get(cell + step, false) and not seen.has(cell + step):
					open.append(cell + step)
		(
			assert_bool(walks_in)
			. override_failure_message("no walk from the room up to a spot that sees " + what)
			. is_true()
		)


func test_each_box_lies_on_storage_s_floor_clear_of_the_level() -> void:
	for tag: StringName in BOX_TAGS:
		for at: Vector3 in _read.layout.positions(tag):
			var floor_at := _world.floor_below(at + Vector3.UP * 0.1)
			var what := "the %s marker at %s" % [tag, at]
			assert_bool(floor_at != WorldQuery.NO_FLOOR).override_failure_message(what).is_true()
			assert_float(absf(at.y - floor_at.y)).override_failure_message(what).is_less(FLOOR_M)
			# In the basement (storage, level -1), inside nothing solid.
			assert_float(at.y).override_failure_message(what).is_equal_approx(-3.2, NEAR)
			assert_int(_point_hits(at + Vector3.UP * 0.1)).override_failure_message(what).is_equal(
				0
			)
	# The check can fail: the same point inside the bun shelf's collision.
	assert_int(_point_hits(Vector3(16, -3.2 + 0.1, 20.75))).is_greater(0)


func test_no_other_marker_shares_a_cooking_marker_s_x_and_z() -> void:
	var layout := _read.layout
	for tag: StringName in STATION_TAGS + BOX_TAGS:
		for spot: Vector3 in layout.positions(tag):
			for other: StringName in layout.tags():
				for at: Vector3 in layout.positions(other):
					if at == spot:
						continue
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


func test_no_other_map_holds_a_cooking_marker() -> void:
	for path: String in OTHER_MAPS:
		var read := MarkerReader.read_scene(path, HostWorldQuery.new())
		for tag: StringName in STATION_TAGS + BOX_TAGS:
			var what := "%s holds %s markers (CD15)" % [path, tag]
			assert_int(read.layout.count(tag)).override_failure_message(what).is_equal(0)


## §6's Burgers rows as [tag, world point]: plan (x, y) at level L is (x, L * 3.2, y).
func _doc_points() -> Array[Array]:
	var points: Array[Array] = []
	var row := RegEx.create_from_string(
		"^\\| Burgers \\| ([^|]+?) \\| (-?\\d+) \\| (-?[\\d.]+), (-?[\\d.]+) \\|"
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


func _point_hits(at: Vector3) -> int:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = at
	query.collision_mask = LevelWorld.WORLD_LAYER
	return _level.space_state().intersect_point(query).size()


## How many shapes of the House's world a standing player's capsule (the base mode's
## PlayerRules) meets with its feet on the floor at `feet`.
func _hits(feet: Vector3) -> int:
	var rules := (load(BASE_MODE) as GameMode).player_rules
	var capsule := CapsuleShape3D.new()
	capsule.radius = rules.capsule_radius_m
	capsule.height = rules.capsule_height_m - FLOOR_GAP_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	var centre := feet + Vector3.UP * (FLOOR_GAP_M + capsule.height / 2.0)
	query.transform = Transform3D(Basis.IDENTITY, centre)
	return _level.space_state().intersect_shape(query).size()
