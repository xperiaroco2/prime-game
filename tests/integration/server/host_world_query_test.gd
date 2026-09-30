extends GdUnitTestSuite
## HostWorldQuery (ARCHITECTURE §4.5, §7.1; E9, E10): WorldQuery answered by rays in the host's
## LevelWorld of the level Match names. Fixture level tests/fixtures/levels/wall_ledge_crate.tscn,
## floor top at y = 0 over x and z in -20..20:
## - a wall 0.2 m thick (x 4.9..5.1), 3 m high, over z -5..5;
## - a ledge with its top at 0.3 over x -10..-6, z -2..2;
## - a low crate with its top at 0.5 over x -0.5..0.5, z 5.5..6.5.
## platform_room.tscn: a floor, and a platform with its top at 1 over x -1..1, z 5..7.

const LEVEL := "res://tests/fixtures/levels/wall_ledge_crate.tscn"
const ROOM := "res://tests/fixtures/levels/platform_room.tscn"
## The fixture mode's capsule radius (FixtureModes.player_rules).
const RADIUS := 0.4
const NEAR := Vector3(1e-3, 1e-3, 1e-3)


func test_with_no_level_it_answers_like_an_empty_world() -> void:
	var query := HostWorldQuery.new(RADIUS)
	query.add_level(LevelWorld.build(LEVEL))
	assert_str(query.level_path()).is_empty()
	assert_vector(query.floor_below(Vector3(0, 5, 0))).is_equal(WorldQuery.NO_FLOOR)
	assert_bool(query.line_of_sight(Vector3(0, 1, 0), Vector3(10, 1, 0))).is_true()
	query.use_level(LEVEL)
	assert_str(query.level_path()).is_equal(LEVEL)
	assert_vector(query.floor_below(Vector3(0, 5, 0))).is_equal_approx(Vector3.ZERO, NEAR)
	query.use_level("")
	assert_str(query.level_path()).is_empty()
	assert_vector(query.floor_below(Vector3(0, 5, 0))).is_equal(WorldQuery.NO_FLOOR)
	query.use_level("res://tests/fixtures/levels/unknown.tscn")
	assert_str(query.level_path()).is_empty()
	assert_vector(query.stand_floor_below(Vector3(0, 5, 0))).is_equal(WorldQuery.NO_FLOOR)


func test_use_level_switches_between_the_levels_worlds() -> void:
	var query := HostWorldQuery.new(RADIUS)
	query.add_level(LevelWorld.build(LEVEL))
	query.add_level(LevelWorld.build(ROOM))
	assert_bool(query.has_level(LEVEL)).is_true()
	assert_bool(query.has_level(ROOM)).is_true()
	query.use_level(ROOM)
	assert_float(query.floor_below(Vector3(0, 5, 6)).y).is_equal_approx(1.0, 1e-3)
	query.use_level(LEVEL)
	assert_float(query.floor_below(Vector3(0, 5, 6)).y).is_equal_approx(0.5, 1e-3)


func test_the_wall_blocks_the_line_of_sight() -> void:
	var query := _level()
	assert_bool(query.line_of_sight(Vector3(0, 1.6, 0), Vector3(8, 1.6, 0))).is_false()
	assert_bool(query.line_of_sight(Vector3(8, 1.6, 0), Vector3(0, 1.6, 0))).is_false()
	assert_bool(query.line_of_sight(Vector3(0, 1.6, 0), Vector3(4.8, 1.6, 0))).is_true()
	# Past its end, and over the crate's top.
	assert_bool(query.line_of_sight(Vector3(0, 1.6, 6), Vector3(8, 1.6, 6))).is_true()
	assert_bool(query.line_of_sight(Vector3(0, 0.6, 4), Vector3(0, 0.6, 8))).is_true()
	assert_bool(query.line_of_sight(Vector3(0, 0.4, 4), Vector3(0, 0.4, 8))).is_false()
	assert_bool(query.line_of_sight(Vector3(1, 1, 1), Vector3(1, 1, 1))).is_true()


func test_floor_below_is_one_ray_at_the_point() -> void:
	var query := _level()
	var on_ledge := query.floor_below(Vector3(-7, 1, 1))
	assert_vector(on_ledge).is_equal_approx(Vector3(-7, 0.3, 1), NEAR)
	# Keeps the point's x and z exactly.
	assert_float(on_ledge.x).is_equal(-7.0)
	assert_float(on_ledge.z).is_equal(1.0)
	# Beside the ledge, within a capsule radius of it: the ground.
	assert_float(query.floor_below(Vector3(-5.8, 1, 0)).y).is_equal_approx(0.0, 1e-3)
	# From inside the ledge's box a ray does not hit the box (hit_from_inside is off): the ground.
	assert_float(query.floor_below(Vector3(-8, 0.1, 0)).y).is_equal_approx(0.0, 1e-3)
	# Past the floor's edge: nothing.
	assert_vector(query.floor_below(Vector3(30, 1, 0))).is_equal(WorldQuery.NO_FLOOR)
	assert_vector(query.floor_below(Vector3(0, -1, 0))).is_equal(WorldQuery.NO_FLOOR)


func test_stand_floor_below_is_the_highest_floor_under_the_footprint() -> void:
	var query := _level()
	# On the ledge's edge (at x = -6), asked from a little above its top, the capsule's centre
	# 0.3 m past it: the -x ray lands on the ledge, the centre's ray on the ground.
	var feet := Vector3(-5.7, 0.4, 0)
	assert_vector(query.stand_floor_below(feet)).is_equal_approx(Vector3(-5.7, 0.3, 0), NEAR)
	assert_float(query.floor_below(feet).y).is_equal_approx(0.0, 1e-3)
	# Past the radius: the ground.
	assert_float(query.stand_floor_below(Vector3(-5.5, 0.4, 0)).y).is_equal_approx(0.0, 1e-3)
	# Beside the crate on +z and -z, and on its top.
	assert_float(query.stand_floor_below(Vector3(0, 0.6, 6.8)).y).is_equal_approx(0.5, 1e-3)
	assert_float(query.stand_floor_below(Vector3(0, 0.6, 5.2)).y).is_equal_approx(0.5, 1e-3)
	assert_float(query.stand_floor_below(Vector3(0, 0.6, 6)).y).is_equal_approx(0.5, 1e-3)
	# The footprint does not reach floors above the feet.
	assert_float(query.stand_floor_below(Vector3(0, 0.1, 5.2)).y).is_equal_approx(0.0, 1e-3)
	# With a radius of 0 it is floor_below().
	var one_ray := _level(0.0)
	assert_float(one_ray.stand_floor_below(feet).y).is_equal_approx(0.0, 1e-3)
	# At the edge of the world, one ray of five on the floor is enough.
	assert_float(query.stand_floor_below(Vector3(20.3, 0.1, 0)).y).is_equal_approx(0.0, 1e-3)
	assert_vector(query.stand_floor_below(Vector3(21, 0.1, 0))).is_equal(WorldQuery.NO_FLOOR)


func test_rest_position_stops_before_the_wall_and_drops_to_the_floor() -> void:
	var query := _level()
	var at := query.rest_position(Vector3(4, 1.6, 0), Vector3(6, 1.6, 0))
	# The wall's face at x = 4.9, less HostWorldQuery.WALL_STOP_M.
	assert_vector(at).is_equal_approx(Vector3(4.7, 0, 0), NEAR)
	# Hard against the wall: stopped at the start, never behind it.
	var close := query.rest_position(Vector3(4.8, 1.6, 0), Vector3(6, 1.6, 0))
	assert_vector(close).is_equal_approx(Vector3(4.8, 0, 0), NEAR)
	# Nothing in the way: at the target, on the floor.
	var clear := query.rest_position(Vector3(0, 1.6, 0), Vector3(0, 1.6, -1))
	assert_vector(clear).is_equal_approx(Vector3(0, 0, -1), NEAR)


func test_rest_position_on_the_low_crate_and_past_the_floor() -> void:
	var query := _level()
	var on_crate := query.rest_position(Vector3(0, 1.6, 5), Vector3(0, 1.6, 6))
	assert_vector(on_crate).is_equal_approx(Vector3(0, 0.5, 6), NEAR)
	# Past the floor's edge there is no floor: the stop itself.
	var off := query.rest_position(Vector3(19.5, 1.6, 0), Vector3(20.5, 1.6, 0))
	assert_vector(off).is_equal_approx(Vector3(20.5, 1.6, 0), NEAR)


## E10 (b)'s case: the player stands on the ledge's edge (its footprint holds it at the ledge's
## height), and the package it puts down beside the ledge rests on the ground, where the delivery
## check reads its height; the footprint there would have put it at the ledge's height.
func test_a_package_put_down_beside_the_ledge_rests_on_the_ground() -> void:
	var mode := FixtureItemModes.basic()
	var query := HostWorldQuery.new(mode.player_rules.capsule_radius_m)
	var scene := (load(LEVEL) as PackedScene).instantiate()
	query.add_level(LevelWorld.from_scene(scene, FixtureModes.LOBBY))
	query.add_level(LevelWorld.from_scene(scene, FixtureModes.MAP))
	scene.free()
	var game := FixtureItemModes.in_round(mode, [1, 2], query)
	assert_str(query.level_path()).is_equal(FixtureModes.MAP)
	FixtureItemModes.stand(game, 1, Vector3(-5.7, 0.3, 0))
	var item := FixtureItemModes.lay(game, &"package", Vector3(-5.7, 0, 0.5))
	FixtureItemModes.pick_up(game, 1, item)
	assert_int(game.state.player(1).held_item).is_equal(item.id)
	FixtureItemModes.put_down(game, 1, Vector3(0, 0, 1))
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	assert_vector(item.position).is_equal_approx(Vector3(-5.7, 0, 1), NEAR)
	# The eye was at the ledge's height plus 1.6 m; the footprint from there reaches the ledge.
	assert_float(query.stand_floor_below(Vector3(-5.7, 1.9, 1)).y).is_equal_approx(0.3, 1e-3)
	assert_array(Array(game.diagnostics)).is_empty()


func test_for_mode_builds_every_level_with_the_mode_s_capsule_radius() -> void:
	var mode := FixtureModes.basic()
	mode.lobby_level = ROOM
	mode.maps = PackedStringArray([LEVEL, ROOM])
	var query := HostWorldQuery.for_mode(mode)
	assert_array(Array(query.errors)).is_empty()
	assert_bool(query.has_level(ROOM)).is_true()
	assert_bool(query.has_level(LEVEL)).is_true()
	assert_float(query.footprint_radius).is_equal(RADIUS)
	mode.maps = PackedStringArray(["res://tests/scratch/no_such_level.tscn"])
	var broken := HostWorldQuery.for_mode(mode)
	assert_int(broken.errors.size()).is_equal(1)
	assert_str(broken.errors[0]).contains("no_such_level").contains("not a scene")


func _level(radius: float = RADIUS) -> HostWorldQuery:
	var query := HostWorldQuery.new(radius)
	query.add_level(LevelWorld.build(LEVEL))
	query.use_level(LEVEL)
	return query
