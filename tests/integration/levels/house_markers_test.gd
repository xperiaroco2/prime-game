extends GdUnitTestSuite
## The House map carries what the base mode asks of a map (ARCHITECTURE §9.4, §9.6): read by the
## host's marker reader in the host's world of the map, its markers raise no error (each delivery
## circle and zone stands on a floor, no marker has two tags) and the layout check of a mode that
## plays on it finds nothing missing for the mode's maximum of players. Its zone markers (#651,
## M7-Z5; ZD10 (a), provisional until the engineer moves them) keep ZE9's spacing, fit the mode
## at the most zones and packages, and each zone's cylinder stands on flat floor clear of walls,
## ceilings and furniture (the convention in `levels/CLAUDE.md`, checked here in the host's
## collision world; a `shot` still shows it). The map is not in the base mode's list yet (#623):
## the scenarios' fake world is one flat floor.

const Spacing := preload("res://tests/unit/content/zone_spacing.gd")
const MAP := "res://levels/house/house.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## The cylinder's bottom this far above the floor its marker snaps to, so that floor is no hit.
const FLOOR_GAP_M := 0.05
## How far the floor under a zone may differ from its marker's floor: float noise, no step.
const FLAT_M := 0.01
## How many points on each ring under a zone the flat-floor test samples.
const RING_POINTS := 16


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
	assert_int(layout.count(&"circle")).is_equal(10)
	assert_int(layout.count(&"knife")).is_equal(4)
	assert_int(layout.count(&"respawn")).is_equal(4)
	# #651's provisional points, one per floor but the attic (#302 comment 6085904317).
	assert_int(layout.count(&"zone")).is_equal(3)


func test_the_zones_keep_ze9_s_spacing() -> void:
	var mode := _base_mode()
	var zone := Spacing.zone_task(mode).zone
	var layout := _read(mode).layout
	assert_int(layout.count(zone.spawn_tag)).is_greater(0)
	assert_array(Array(Spacing.faults(MAP, layout, zone, Spacing.circle(mode)))).is_empty()


func test_the_house_fits_ten_players_at_the_most_zones_and_packages() -> void:
	var mode := _house_mode()
	var zone := Spacing.zone_task(mode)
	var map := _read(mode).layout
	var settings := mode.default_settings()
	settings[&"zones"] = mode.find_setting(&"zones").max_value
	settings[&"packages"] = mode.find_setting(&"packages").max_value
	var demands := LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, settings, mode.max_players)
	assert_array(Array(demands.shortfalls(map))).is_empty()
	assert_int(demands.markers.get(&"zone", 0)).is_equal(settings[&"zones"])
	assert_int(zone.zone.palette.size()).is_greater_equal(settings[&"zones"])
	assert_int(map.count(&"zone")).is_greater_equal(settings[&"zones"])


func test_each_zone_stands_on_flat_floor_clear_of_walls_and_ceilings() -> void:
	var mode := _base_mode()
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


func test_the_clearance_check_refuses_a_zone_by_a_wall_or_over_the_stairs() -> void:
	# The check above can fail: a zone pressed to the landing's west wall, and one over the main
	# stairs' well (docs/design/house-map.md §5: they reach the landing at x 28, y 33).
	var zone := Spacing.zone_task(_base_mode()).zone
	var level := LevelWorld.build(MAP)
	var world := _world(level)
	var by_wall := world.floor_below(Vector3(26.5, 4.2, 41))
	assert_int(_hits(level, by_wall, zone)).is_greater(0)
	var over_stairs := world.floor_below(Vector3(29.5, 4.2, 35))
	assert_float(_floor_step(world, over_stairs, zone.radius_m)).is_greater(FLAT_M)


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


func _base_mode() -> GameMode:
	return load(BASE_MODE) as GameMode


## The base mode playing on the House alone, with no lobby.
func _house_mode() -> GameMode:
	var mode := _base_mode().duplicate() as GameMode
	mode.lobby_level = ""
	mode.maps = PackedStringArray([MAP])
	return mode


func _world(level: LevelWorld) -> HostWorldQuery:
	var world := HostWorldQuery.new()
	world.add_level(level)
	world.use_level(MAP)
	return world


func _read(mode: GameMode) -> MarkerReader.Read:
	return MarkerReader.read_scene(
		MAP, _world(LevelWorld.build(MAP)), MarkerReader.floor_tags_of(mode)
	)
