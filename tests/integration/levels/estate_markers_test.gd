extends GdUnitTestSuite
## The estate (#1374) carries what the base mode asks of a map (ARCHITECTURE §9.6): read by the
## host's marker reader in the host's world of the map, its markers raise no error and the layout
## check of a mode that plays on the estate alone finds nothing missing for the mode's maximum of
## players. Its round and respawn markers, read as placed, each stand a player on the floor under
## it with a standing capsule clear of the level (house_markers_test.gd's check, #1042); its
## package markers lie on the floor, and none inside a circle; the round's and the respawns' stand
## together on the skat's clearing before its ramp (#1492). The markers' places are placeholders,
## "not a decision", for the engineer to move (#1374's PR, #1492's PR).

const HouseMarkers := preload("res://tests/integration/levels/house_markers_test.gd")
const MAP := "res://levels/estate/estate.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## How far a marker may stand off the floor under it: float noise, no step.
const SPAWN_FLOOR_M := 0.02
## The foot of the skat's mouth ramp (docs/design/estate-map.md §5a: the ship at (116, 72), the
## foot at its (0, -12.6)) and its hinge's z: the round starts and respawns on the clearing before
## it (GDD §3 "The M8 slice", #1492).
const RAMP_FOOT := Vector2(116, 59.4)
const RAMP_HINGE_Z := 63.9
## How far from the ramp's foot a start or respawn marker stands at most: the clearing.
const RAMP_CLEARING_M := 10.5
## Half the ramp's lane (3.3 m wide) and a capsule's radius: no marker stands on the slope.
const RAMP_LANE_HALF_M := 2.05
## How far apart any two start or respawn markers stand at least, so nobody spawns in another.
const MARKERS_APART_M := 1.2


func test_the_markers_read_without_errors_in_the_host_s_world() -> void:
	var read := _read(_base_mode())
	assert_array(Array(read.errors)).is_empty()


func test_a_mode_playing_on_the_estate_finds_every_marker_it_needs() -> void:
	var mode := _estate_mode()
	var layouts: Dictionary[String, LevelLayout] = {MAP: _read(mode).layout}
	assert_array(Array(LayoutCheck.run(mode, layouts))).is_empty()


func test_the_estate_has_a_marker_per_player_and_the_most_packages() -> void:
	var mode := _base_mode()
	var layout := _read(mode).layout
	assert_int(layout.count(&"round_player")).is_greater_equal(mode.max_players)
	assert_int(layout.count(&"package")).is_greater_equal(_max_of(mode, &"packages"))
	assert_int(layout.count(&"circle")).is_greater_equal(_max_of(mode, &"packages"))
	assert_int(layout.count(&"knife")).is_greater_equal(_default_of(mode, &"knives"))
	assert_int(layout.count(&"respawn")).is_greater(0)


func test_the_round_and_the_respawns_start_on_the_skat_s_clearing() -> void:
	var layout := _read(_base_mode()).layout
	var all: Array[Vector2] = []
	for tag: StringName in [&"round_player", &"respawn"]:
		for at: Vector3 in layout.positions(tag):
			var flat := Vector2(at.x, at.z)
			var where := "the %s marker at %s" % [tag, at]
			(
				assert_float(flat.distance_to(RAMP_FOOT))
				. override_failure_message(where + ": not on the clearing before the ramp")
				. is_less_equal(RAMP_CLEARING_M)
			)
			assert_float(at.z).override_failure_message(where + ": past the ramp").is_less(
				RAMP_HINGE_Z
			)
			var on_the_lane := absf(at.x - RAMP_FOOT.x) < RAMP_LANE_HALF_M and at.z >= RAMP_FOOT.y
			assert_bool(on_the_lane).override_failure_message(where + ": on the ramp").is_false()
			for other: Vector2 in all:
				(
					assert_float(flat.distance_to(other))
					. override_failure_message(where + ": too close to the one at %s" % other)
					. is_greater_equal(MARKERS_APART_M)
				)
			all.append(flat)
	assert_int(all.size()).is_greater(0)


func test_each_round_and_respawn_marker_stands_a_player_on_a_floor_clear_of_the_level() -> void:
	var rules := _base_mode().player_rules
	var level := LevelWorld.build(MAP)
	var world := _world(level, rules)
	var layout := (
		MarkerReader.read_scene(MAP, world, MarkerReader.floor_tags_of(_base_mode())).layout
	)
	for tag: StringName in [&"round_player", &"respawn"]:
		var spots := layout.positions(tag)
		assert_int(spots.size()).override_failure_message(String(tag)).is_greater(0)
		for at: Vector3 in spots:
			var where := "the %s marker at %s" % [tag, at]
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


func test_each_package_lies_on_the_floor_outside_every_circle() -> void:
	var mode := _base_mode()
	var world := _world(LevelWorld.build(MAP), mode.player_rules)
	var layout := MarkerReader.read_scene(MAP, world, MarkerReader.floor_tags_of(mode)).layout
	var circle := _circle_kind(mode)
	assert_object(circle).is_not_null()
	for at: Vector3 in layout.positions(&"package"):
		var floor_at := world.floor_below(Items.lifted(at))
		(
			assert_float(absf(floor_at.y - at.y))
			. override_failure_message("the package marker at %s: off the floor" % at)
			. is_less_equal(SPAWN_FLOOR_M)
		)
		for centre: Vector3 in layout.positions(&"circle"):
			(
				assert_float(Vector2(at.x, at.z).distance_to(Vector2(centre.x, centre.z)))
				. override_failure_message(
					"the package at %s lies in the circle at %s" % [at, centre]
				)
				. is_greater(circle.radius_m)
			)


## levels/CLAUDE.md: a station marker sits on flat floor. The host snaps a circle marker down onto
## the floor below it, so one over a hole (a passage's manhole, #1373) would read below the ground,
## on its ramp: each reads at the height it is placed at, and the floor under its rim is as high.
func test_each_circle_reads_where_it_stands_on_a_flat_floor() -> void:
	var mode := _base_mode()
	var world := _world(LevelWorld.build(MAP), mode.player_rules)
	var no_tags: Array[StringName] = []
	var placed := MarkerReader.read_scene(MAP, world, no_tags).layout.positions(&"circle")
	var read := (
		MarkerReader
		. read_scene(MAP, world, MarkerReader.floor_tags_of(mode))
		. layout
		. positions(&"circle")
	)
	var circle := _circle_kind(mode)
	assert_object(circle).is_not_null()
	assert_int(read.size()).is_equal(placed.size())
	for i in mini(read.size(), placed.size()):
		var where := "the circle marker at %s" % placed[i]
		(
			assert_float(absf(read[i].y - placed[i].y))
			. override_failure_message(where + ": read at %s" % read[i])
			. is_less_equal(SPAWN_FLOOR_M)
		)
		for step in 8:
			var rim := (
				placed[i] + Vector3.FORWARD.rotated(Vector3.UP, step * TAU / 8) * circle.radius_m
			)
			var floor_at := world.floor_below(Items.lifted(rim))
			(
				assert_float(absf(floor_at.y - placed[i].y))
				. override_failure_message(
					where + ": the floor at its rim %s is %s" % [rim, floor_at]
				)
				. is_less_equal(SPAWN_FLOOR_M)
			)


func _base_mode() -> GameMode:
	return load(BASE_MODE) as GameMode


## The base mode playing on the estate alone, with no lobby.
func _estate_mode() -> GameMode:
	var mode := _base_mode().duplicate() as GameMode
	mode.lobby_level = ""
	mode.maps = PackedStringArray([MAP])
	mode.bench_maps = PackedStringArray()
	return mode


func _circle_kind(mode: GameMode) -> StationKind:
	for type: TaskType in mode.task_types:
		if type is Delivery and (type as Delivery).maps.has(MAP):
			return (type as Delivery).circle
	return null


func _max_of(mode: GameMode, id: StringName) -> int:
	for setting: SettingSpec in mode.settings:
		if setting != null and setting.id == id:
			return setting.max_value
	return 0


func _default_of(mode: GameMode, id: StringName) -> int:
	return mode.default_settings().get(id, 0)


func _world(level: LevelWorld, rules: PlayerRules) -> HostWorldQuery:
	var world := HostWorldQuery.new(rules.capsule_radius_m, rules.crouch_height_m)
	world.add_level(level)
	world.use_level(MAP)
	return world


func _read(mode: GameMode) -> MarkerReader.Read:
	return MarkerReader.read_scene(
		MAP, _world(LevelWorld.build(MAP), mode.player_rules), MarkerReader.floor_tags_of(mode)
	)
