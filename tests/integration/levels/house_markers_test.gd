extends GdUnitTestSuite
## The House map carries what the base mode asks of a map (ARCHITECTURE §9.4, §9.6): read by the
## host's marker reader in the host's world of the map, its markers raise no error (each station
## marker, a drop-off, a zone or the study's last circle, stands on a floor; no marker has two
## tags) and the layout check of a mode that plays on it finds nothing missing for the mode's
## maximum of players. Its zone markers (#651,
## M7-Z5; ZD10 (a), provisional until the engineer moves them) keep ZE9's spacing, fit the mode
## at the most zones and packages, and each zone's cylinder stands on flat floor clear of walls,
## ceilings and furniture (the convention in `levels/CLAUDE.md`, checked here in the host's
## collision world; a `shot` still shows it). Its round and respawn markers, read as placed, each
## stand a player on the floor under it with a standing capsule clear of the level (#1042). The
## House is the base mode's second map (#626); the scenarios play only its flat first map
## (ARCHITECTURE §9.7), whose fake world is one flat floor. The zone checks read the zone task
## from FixtureBaseModeWithZones: the engineer took it out of the shipped base mode on #842, and
## the House keeps its zones.

const Spacing := preload("res://tests/fixtures/tasks/fixture_zone_spacing.gd")
const MAP := "res://levels/house/house.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## The cylinder's bottom this far above the floor its marker snaps to, so that floor is no hit.
const FLOOR_GAP_M := 0.05
## How far the floor under a zone may differ from its marker's floor: float noise, no step.
const FLAT_M := 0.01
## How many points on each ring under a zone the flat-floor test samples.
const RING_POINTS := 16
## How far a round or respawn marker may stand off the floor under it: float noise, no step.
const SPAWN_FLOOR_M := 0.02
## A point on the house's south wall (docs/design/house-map.md: x 18..42, y 24..44), west of
## the front door, for the spawn check's refusal case.
const SOUTH_WALL := Vector3(21.0, 1.0, 44.0)


func test_the_markers_read_without_errors_in_the_host_s_world() -> void:
	var read := _read(_base_mode())
	assert_array(Array(read.errors)).is_empty()


func test_a_mode_playing_on_the_house_finds_every_marker_it_needs() -> void:
	var mode := _house_mode()
	var layouts: Dictionary[String, LevelLayout] = {MAP: _read(mode).layout}
	assert_array(Array(LayoutCheck.run(mode, layouts))).is_empty()


func test_the_markers_are_the_engineer_s_counts() -> void:
	var layout := _read(_base_mode()).layout
	assert_int(layout.count(&"round_player")).is_equal(10)
	assert_int(layout.count(&"package")).is_equal(10)
	# Today's colour Delivery deals on the greybox alone (DE9), so the House's ten circles went
	# (#831), all but the study's Circle10: the study has its own owner (#783, PR #1058), and its
	# follow-up removes it, this count then 0.
	assert_int(layout.count(&"circle")).is_equal(1)
	assert_int(layout.count(&"knife")).is_equal(4)
	assert_int(layout.count(&"respawn")).is_equal(4)
	# #651's provisional points (#302 comment 6085904317): the yard and the garden on the ground
	# floor, the landing upstairs; none in the basement, where the scenarios' flat fake finds no
	# floor (#681).
	assert_int(layout.count(&"zone")).is_equal(3)


func test_the_zones_keep_ze9_s_spacing() -> void:
	var mode := _zone_mode()
	var zone := Spacing.zone_task(mode).zone
	var layout := _read(mode).layout
	assert_int(layout.count(zone.spawn_tag)).is_greater(0)
	assert_array(Array(Spacing.faults(MAP, layout, zone, Spacing.others(mode)))).is_empty()


func test_the_house_fits_ten_players_at_the_most_zones_and_packages() -> void:
	var mode := _house_mode(_zone_mode())
	var zone := Spacing.zone_task(mode)
	var map := _read(mode).layout
	var settings := mode.default_settings()
	settings[&"zones"] = mode.find_setting(&"zones").max_value
	settings[&"packages"] = mode.find_setting(&"packages").max_value
	var demands := LayoutCheck.demands_of(
		mode, PhaseSpec.Level.MAP, settings, mode.max_players, {}, MAP
	)
	assert_array(Array(demands.shortfalls(map))).is_empty()
	assert_int(demands.markers.get(&"zone", 0)).is_equal(settings[&"zones"])
	assert_int(zone.zone.palette.size()).is_greater_equal(settings[&"zones"])
	assert_int(map.count(&"zone")).is_greater_equal(settings[&"zones"])


func test_each_zone_stands_on_flat_floor_clear_of_walls_and_ceilings() -> void:
	var mode := _zone_mode()
	var zone := Spacing.zone_task(mode).zone
	var level := LevelWorld.build(MAP)
	var world := _world(level)
	var read := MarkerReader.read_scene(MAP, world, MarkerReader.floor_tags_of(mode))
	var zones := read.layout.positions(zone.spawn_tag)
	assert_int(zones.size()).is_greater(0)
	for at: Vector3 in zones:
		(
			assert_int(_hits(level, at, zone))
			. override_failure_message(
				"the zone at %s: its cylinder meets a wall, a ceiling or furniture" % at
			)
			. is_equal(0)
		)
		(
			assert_float(_floor_step(world, at, zone.radius_m))
			. override_failure_message("the zone at %s: its floor is not flat" % at)
			. is_less_equal(FLAT_M)
		)


func test_the_clearance_check_refuses_a_zone_by_a_wall_a_ceiling_or_over_the_stairs() -> void:
	# The check above can fail: a zone pressed to the landing's west wall, one over the main
	# stairs' well (docs/design/house-map.md §5: they reach the landing at x 28, y 33) and one in
	# the attic, whose ceiling (2.2 m over its floor) is lower than the zone's cylinder.
	var zone := Spacing.zone_task(_zone_mode()).zone
	var level := LevelWorld.build(MAP)
	var world := _world(level)
	var by_wall := world.floor_below(Vector3(26.5, 4.2, 41))
	_assert_floor_found(by_wall, "by the wall")
	assert_int(_hits(level, by_wall, zone)).is_greater(0)
	var over_stairs := world.floor_below(Vector3(29.5, 4.2, 35))
	_assert_floor_found(over_stairs, "over the stairs")
	assert_float(_floor_step(world, over_stairs, zone.radius_m)).is_greater(FLAT_M)
	var under_ceiling := world.floor_below(Vector3(30, 7.4, 35))
	_assert_floor_found(under_ceiling, "under the attic's ceiling")
	assert_int(_hits(level, under_ceiling, zone)).is_greater(0)


## A refusal case whose probe found no floor would pass for the wrong reason (NO_FLOOR is INF).
func _assert_floor_found(floor_point: Vector3, case_name: String) -> void:
	(
		assert_bool(floor_point != WorldQuery.NO_FLOOR)
		. override_failure_message("no floor found for the refusal case %s" % case_name)
		. is_true()
	)


## How many collision shapes on the world layer the zone's cylinder at `at` (its snapped floor
## point) meets between FLOOR_GAP_M above the floor and its height.
static func _hits(level: LevelWorld, at: Vector3, zone: StationKind) -> int:
	var cylinder := CylinderShape3D.new()
	cylinder.radius = zone.radius_m
	cylinder.height = zone.height_m - FLOOR_GAP_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = cylinder
	query.collision_mask = LevelWorld.WORLD_LAYER
	var centre := at + Vector3.UP * (FLOOR_GAP_M + cylinder.height / 2.0)
	query.transform = Transform3D(Basis.IDENTITY, centre)
	return level.space_state().intersect_shape(query).size()


## The largest difference between the floor at `at` and the floor under points on two rings
## around it (half the radius and just inside the radius); a hole is an infinite step.
static func _floor_step(world: HostWorldQuery, at: Vector3, radius: float) -> float:
	var step := 0.0
	for ring: float in [radius / 2.0, radius - 0.01]:
		for i in RING_POINTS:
			var angle := TAU * i / RING_POINTS
			var point := at + Vector3(cos(angle) * ring, 1.0, sin(angle) * ring)
			var under := world.floor_below(point)
			if under == WorldQuery.NO_FLOOR:
				return INF
			step = maxf(step, absf(under.y - at.y))
	return step


func test_each_round_and_respawn_marker_stands_a_player_on_a_floor_clear_of_the_level() -> void:
	# The round's spawns (the yard, on the plot's ground: the walk starts there) and the respawns
	# are read as placed, never snapped: each marker stands on the floor under it (within
	# SPAWN_FLOOR_M) and a standing player's capsule there meets no collider of the level.
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
				assert_float(_off_the_floor(world, at, rules))
				. override_failure_message(where + ": not on the floor under it")
				. is_less_equal(SPAWN_FLOOR_M)
			)
			(
				assert_int(_standing_hits(level, at, rules))
				. override_failure_message(where + ": a standing player does not fit there")
				. is_equal(0)
			)


func test_the_spawn_check_refuses_a_marker_in_the_ground_or_against_a_wall() -> void:
	# The check above can fail: a yard spawn 10 cm into the plot's ground (as the yard's markers
	# stood at y -0.06 before #523's fix), one 30 cm above it, and one on the house's south wall.
	var rules := _base_mode().player_rules
	var level := LevelWorld.build(MAP)
	var world := _world(level, rules)
	var spawn := (
		MarkerReader
		. read_scene(MAP, world, MarkerReader.floor_tags_of(_base_mode()))
		. layout
		. positions(&"round_player")[0]
	)
	var buried := spawn + Vector3.DOWN * 0.1
	assert_float(_off_the_floor(world, buried, rules)).is_greater(SPAWN_FLOOR_M)
	assert_int(_standing_hits(level, buried, rules)).is_greater(0)
	assert_float(_off_the_floor(world, spawn + Vector3.UP * 0.3, rules)).is_greater(SPAWN_FLOOR_M)
	var by_wall := world.floor_below(SOUTH_WALL)
	_assert_floor_found(by_wall, "on the south wall")
	assert_int(_standing_hits(level, by_wall, rules)).is_greater(0)


## How far `at` lies from the floor a player with its feet there stands on (as
## house_knife_launch_test.gd reads a rest: the capsule's footprint, from a radius above); no
## floor is INF.
static func _off_the_floor(world: HostWorldQuery, at: Vector3, rules: PlayerRules) -> float:
	var floor_at := world.stand_floor_below(Items.lifted(at + Vector3.UP * rules.capsule_radius_m))
	if floor_at == WorldQuery.NO_FLOOR:
		return INF
	return absf(floor_at.y - at.y)


## How many colliders on the world layer a standing player's capsule with its feet at `at` meets,
## lifted by Items.SURFACE_CLEARANCE_M and narrowed by it (touching the floor or a wall is no hit).
static func _standing_hits(level: LevelWorld, at: Vector3, rules: PlayerRules) -> int:
	var capsule := CapsuleShape3D.new()
	capsule.radius = rules.capsule_radius_m - Items.SURFACE_CLEARANCE_M
	capsule.height = rules.capsule_height_m
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	var centre := at + Vector3.UP * (rules.capsule_height_m / 2.0 + Items.SURFACE_CLEARANCE_M)
	query.transform = Transform3D(Basis.IDENTITY, centre)
	return level.space_state().intersect_shape(query).size()


func test_each_drop_off_has_one_marker_and_no_item_spawns_inside_one() -> void:
	# DE12 of the delivery-by-meaning ADR (#828): the House's Delivery by meaning finds one marker
	# per drop-off tag, and no marker of its items' spawn tags lies in a drop-off's cylinder at its
	# snapped floor (an item there would spawn delivered).
	var mode := _base_mode()
	var delivery := mode.find_task_type(&"delivery") as DeliveryByMeaning
	assert_object(delivery).is_not_null()
	if delivery == null:
		return
	assert_bool(delivery.plays_on(MAP)).is_true()
	var layout := _read(mode).layout
	var kinds := delivery.station_kinds()
	assert_int(kinds.size()).is_equal(4)
	for kind: StationKind in kinds:
		var tag := kind.spawn_tag
		assert_int(layout.count(tag)).override_failure_message(tag).is_equal(1)
		for at: Vector3 in layout.positions(tag):
			var drop_off := StationState.new(0, kind, at, Color.WHITE)
			# The check can fail: the drop-off's own spot is inside it.
			assert_bool(drop_off.contains(at)).is_true()
			for item_tag: StringName in delivery.item_spawn_tags():
				for spot: Vector3 in layout.positions(item_tag):
					var inside := "%s marker at %s lies in %s" % [item_tag, spot, kind.id]
					assert_bool(drop_off.contains(spot)).override_failure_message(inside).is_false()


func _base_mode() -> GameMode:
	return load(BASE_MODE) as GameMode


## The base mode with the zone task (#649's; a fixture since the engineer took the zone task out
## of the shipped base mode, #842): the zone checks read their zone kind and numbers from it.
func _zone_mode() -> GameMode:
	return FixtureBaseModeWithZones.mode()


## `base` (the base mode by default) playing on the House alone, with no lobby.
func _house_mode(base: GameMode = null) -> GameMode:
	var mode := (base if base != null else _base_mode()).duplicate() as GameMode
	mode.lobby_level = ""
	mode.maps = PackedStringArray([MAP])
	return mode


func _world(level: LevelWorld, rules: PlayerRules = null) -> HostWorldQuery:
	var world := (
		HostWorldQuery.new()
		if rules == null
		else HostWorldQuery.new(rules.capsule_radius_m, rules.crouch_height_m)
	)
	world.add_level(level)
	world.use_level(MAP)
	return world


func _read(mode: GameMode) -> MarkerReader.Read:
	return MarkerReader.read_scene(
		MAP, _world(LevelWorld.build(MAP)), MarkerReader.floor_tags_of(mode)
	)
