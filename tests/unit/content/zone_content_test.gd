extends GdUnitTestSuite
## The base mode's zone task in `content/` (ARCHITECTURE §9.5.17; the zone task ADR, ZD7, ZD8 (a),
## ZE9; #649): Hold the zone with the engineer's provisional numbers and names (#302 comment
## 6085251071), its `zones` setting, the greybox's fit at the most zones and packages, and ZE9's
## spacing on every map of the base mode (`fixture_zone_spacing.gd`, which the House map's
## marker test shares, #651). Every map is read as the host reads it, in its own collision world,
## as `tests/integration/levels/house_markers_test.gd` reads House (#681): the scenarios' flat
## fake puts House's storeys on one floor, which hides a spawn point beside an upstairs zone. The
## wall and ceiling clearance is a level convention (`levels/CLAUDE.md`), checked by a `shot`,
## and on House by its marker test too. Like the mode check, this test loads `content/` on
## purpose (§9.6).

const Spacing := preload("res://tests/fixtures/tasks/fixture_zone_spacing.gd")
const BASE_MODE := "res://content/modes/base_mode.tres"


func test_hold_the_zone_has_the_engineer_s_provisional_values() -> void:
	var zone := Spacing.zone_task(_mode())
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
	var zone := Spacing.zone_task(mode)
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
	assert_bool(mode.task_types.has(Spacing.zone_task(mode))).is_true()


func test_the_greybox_fits_ten_players_at_the_most_zones_and_packages() -> void:
	var mode := _mode()
	var zone := Spacing.zone_task(mode)
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
	var zone := Spacing.zone_task(mode).zone
	var circle := Spacing.circle(mode)
	var layouts := _layouts(mode)
	for path: String in mode.maps:
		var map := layouts[path]
		assert_int(map.count(zone.spawn_tag)).override_failure_message(path).is_greater(0)
		assert_array(Array(Spacing.faults(path, map, zone, circle))).is_empty()


func test_the_spacing_check_refuses_a_zone_on_a_spawn_point() -> void:
	# The check above can fail: a zone marker 2 m from a round_player marker (2.5 m needed).
	var mode := _mode()
	var zone := Spacing.zone_task(mode).zone
	var near := Spacing.apart(Vector3(0, 0, 2), Vector3.ZERO, zone.radius_m + Spacing.FREE_M, 2.5)
	assert_bool(near).is_false()
	# A marker a storey above is not compared.
	assert_bool(Spacing.apart(Vector3(0, 3.2, 0), Vector3.ZERO, 3.0, zone.height_m)).is_true()
	# The same through faults(): a map with a zone 2 m from a spawn point has one fault.
	var map := LevelLayout.new()
	map.add_marker(zone.spawn_tag, Vector3(0, 0, 2))
	map.add_marker(&"round_player", Vector3.ZERO)
	var faults := Spacing.faults("a map", map, zone, Spacing.circle(mode))
	assert_array(Array(faults)).has_size(1)


func test_the_suite_reads_house_s_storeys_at_their_own_height() -> void:
	# Guards `_layouts`: read through the scenarios' flat fake, every zone snaps to y = 0, so House's
	# upstairs zone (the landing's) would sit at the ground floor and a flat read would pass (#681).
	var mode := _mode()
	var zone := Spacing.zone_task(mode).zone
	var house := _layouts(mode)["res://levels/house/house.tscn"]
	var top := 0.0
	for at: Vector3 in house.positions(zone.spawn_tag):
		top = maxf(top, at.y)
	assert_float(top).override_failure_message("House's zones were read flat").is_greater(
		zone.height_m
	)


func test_the_flat_fake_would_hide_a_spawn_point_beside_an_upstairs_zone() -> void:
	# Why this suite reads every map in the host's world (#681): the scenarios' flat fake snaps a
	# station marker to its one floor at y = 0 but leaves a spawn point at its storey's height, so
	# a zone 2 m from a spawn point upstairs looks a storey away and is not compared. Read with
	# the storey's own floor (a flat world at y = 3.2, as the host's would answer), it is a fault.
	var mode := _mode()
	var zone := Spacing.zone_task(mode).zone
	var circle := Spacing.circle(mode)
	var tags := MarkerReader.floor_tags_of(mode)
	var storey: Node3D = auto_free(Node3D.new())
	_add_marker(storey, zone.spawn_tag, Vector3(0, 3.7, 2))
	_add_marker(storey, &"round_player", Vector3(0, 3.2, 0))
	var flat := MarkerReader.read(storey, "upstairs", FlatWorldQuery.new(), tags)
	var host := MarkerReader.read(storey, "upstairs", FlatWorldQuery.new(3.2), tags)
	assert_array(Array(flat.errors + host.errors)).is_empty()
	assert_array(Array(Spacing.faults("flat", flat.layout, zone, circle))).is_empty()
	assert_array(Array(Spacing.faults("host", host.layout, zone, circle))).has_size(1)


func _mode() -> GameMode:
	return load(BASE_MODE) as GameMode


## The layouts of the mode's levels as the host reads them, each in its own collision world
## (HostWorldQuery.for_mode, as HostSession builds it), so every marker keeps its storey. The
## scenarios' flat fake (§9.7) would read House's storeys as one floor (#681): see the test above.
func _layouts(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var world := HostWorldQuery.for_mode(mode)
	assert_array(Array(world.errors)).is_empty()
	var levels := MarkerReader.read_levels(mode, world)
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts


static func _add_marker(root: Node3D, tag: StringName, at: Vector3) -> void:
	var marker := Marker3D.new()
	marker.position = at
	marker.add_to_group(MarkerReader.GROUP_PREFIX + tag, true)
	root.add_child(marker)
