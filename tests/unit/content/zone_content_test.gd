extends GdUnitTestSuite
## The base mode's zone task in `content/` (ARCHITECTURE §9.5.17; the zone task ADR, ZD7, ZD8 (a),
## ZE9; #649): Hold the zone with the engineer's provisional numbers and names (#302 comment
## 6085251071), its `zones` setting, the greybox's fit at the most zones and packages, and ZE9's
## spacing on every map of the base mode: any two zone markers at least twice the zone's radius
## apart; each zone marker at least its radius plus 1 m (the respawn point's free space) from every
## `round_player` and `respawn` marker, and at least its radius plus the circle's from every
## delivery circle's marker. Markers on different storeys (more than a zone's height apart in y)
## are not compared. The wall and ceiling clearance is a level convention (`levels/CLAUDE.md`),
## checked by a `shot`. Like the mode check, this test loads `content/` on purpose (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"
## The respawn point's free space (PlayerRules.respawn_free_m in the base mode), ZE9's 1 m.
const FREE_M := 1.0


func test_hold_the_zone_has_the_engineer_s_provisional_values() -> void:
	var zone := _zone_task(_mode())
	assert_object(zone).is_not_null()
	if zone == null:
		return
	assert_str(zone.id).is_equal("hold_the_zone")
	assert_str(zone.display_name).is_equal("Hold the zone")
	assert_str(zone.description).is_equal("Stand in the zone until it fills.")
	assert_float(zone.seconds).is_equal(10.0)
	assert_int(zone.needed_ticks()).is_equal(10 * Ticks.RATE)
	assert_str(zone.subtasks_setting).is_equal("zones")
	assert_str(zone.zones_rng).is_equal("zones")
	assert_str(zone.zone.id).is_equal("zone")
	assert_str(zone.zone.spawn_tag).is_equal("zone")
	assert_float(zone.zone.radius_m).is_equal(1.5)
	assert_float(zone.zone.height_m).is_equal(2.5)
	# Yellow (ZD7): red and green high, blue low.
	assert_int(zone.zone.palette.size()).is_equal(1)
	var yellow := zone.zone.palette[0]
	assert_bool(yellow.r > 0.8 and yellow.g > 0.8 and yellow.b < 0.2).is_true()


func test_a_jump_inside_stays_inside_the_zone() -> void:
	# ZD7's trade-off: a height below the jump plus the host's slack lets a jump leave the zone.
	var mode := _mode()
	var zone := _zone_task(mode)
	var top := mode.player_rules.jump_height_m + MovementRule.jump_slack(mode.player_rules)
	assert_float(zone.zone.height_m).is_greater_equal(top)


func test_the_zones_setting_and_both_types_in_every_match() -> void:
	var mode := _mode()
	var zones := mode.find_setting(&"zones")
	assert_object(zones).is_not_null()
	if zones == null:
		return
	assert_bool(zones.is_number()).is_true()
	# One zone (the engineer's "1 zone"; the palette's one colour allows no more), "not a decision".
	assert_array([zones.default_value, zones.min_value, zones.max_value]).is_equal([1, 1, 1])
	var tasks := mode.find_setting(&"tasks")
	assert_array([tasks.default_value, tasks.max_value]).is_equal([2, mode.task_types.size()])
	assert_bool(mode.task_types.has(_zone_task(mode))).is_true()


func test_the_greybox_fits_ten_players_at_the_most_zones_and_packages() -> void:
	var mode := _mode()
	var zone := _zone_task(mode)
	var map := _layouts(mode)[mode.maps[0]]
	var settings := mode.default_settings()
	settings[&"zones"] = mode.find_setting(&"zones").max_value
	settings[&"packages"] = mode.find_setting(&"packages").max_value
	var demands := LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, settings, mode.max_players)
	assert_array(Array(demands.shortfalls(map))).is_empty()
	assert_int(demands.markers.get(&"zone", 0)).is_equal(settings[&"zones"])
	assert_int(demands.colours.get(&"zone", 0)).is_equal(settings[&"zones"])
	assert_int(zone.zone.palette.size()).is_greater_equal(settings[&"zones"])
	assert_int(map.count(&"zone")).is_greater_equal(settings[&"zones"])


func test_zone_markers_keep_ze9_s_spacing_on_every_map() -> void:
	var mode := _mode()
	var zone := _zone_task(mode).zone
	var circle := _circle(mode)
	var layouts := _layouts(mode)
	for path: String in mode.maps:
		var map := layouts[path]
		var zones := map.positions(zone.spawn_tag)
		assert_int(zones.size()).override_failure_message(path).is_greater(0)
		for i in zones.size():
			for j in range(i + 1, zones.size()):
				_assert_apart(path, zones[i], zones[j], 2.0 * zone.radius_m, zone.height_m)
			for tag: StringName in [&"round_player", &"respawn"]:
				for at: Vector3 in map.positions(tag):
					_assert_apart(path, zones[i], at, zone.radius_m + FREE_M, zone.height_m)
			for at: Vector3 in map.positions(circle.spawn_tag):
				var height := maxf(zone.height_m, circle.height_m)
				_assert_apart(path, zones[i], at, zone.radius_m + circle.radius_m, height)


func test_the_spacing_check_refuses_a_zone_on_a_spawn_point() -> void:
	# The check above can fail: a zone marker 2 m from a round_player marker (2.5 m needed).
	var mode := _mode()
	var zone := _zone_task(mode).zone
	var gap := Vector3(0, 0, 2).distance_to(Vector3.ZERO)
	assert_bool(_apart(Vector3(0, 0, 2), Vector3.ZERO, zone.radius_m + FREE_M, 2.5)).is_false()
	assert_float(gap).is_less(zone.radius_m + FREE_M)
	# A marker a storey above is not compared.
	assert_bool(_apart(Vector3(0, 3.2, 0), Vector3.ZERO, 3.0, zone.height_m)).is_true()


func _assert_apart(path: String, a: Vector3, b: Vector3, at_least: float, height: float) -> void:
	(
		assert_bool(_apart(a, b, at_least, height))
		. override_failure_message(
			"%s: markers at %s and %s are closer than %.2f m" % [path, a, b, at_least]
		)
		. is_true()
	)


## Whether `a` and `b` are at least `at_least` apart horizontally, or on different storeys (more
## than `height` apart in y).
static func _apart(a: Vector3, b: Vector3, at_least: float, height: float) -> bool:
	if absf(a.y - b.y) > height:
		return true
	return Vector2(a.x - b.x, a.z - b.z).length() >= at_least


func _mode() -> GameMode:
	return load(BASE_MODE) as GameMode


func _layouts(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var levels := MarkerReader.read_levels(mode, FlatWorldQuery.new())
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts


static func _zone_task(mode: GameMode) -> ZoneTask:
	for type: TaskType in mode.task_types:
		if type is ZoneTask:
			return type as ZoneTask
	return null


static func _circle(mode: GameMode) -> StationKind:
	for type: TaskType in mode.task_types:
		if type is Delivery:
			return (type as Delivery).circle
	return null
