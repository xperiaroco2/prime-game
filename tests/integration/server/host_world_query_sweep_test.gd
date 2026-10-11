extends GdUnitTestSuite
## HostWorldQuery.sweep (TE2, TE7 of docs/decisions/2026-10-09-throwing-held-items.md): a sphere
## checked at its start with intersect_shape, then cast along the segment with cast_motion, in the
## host's LevelWorld. wall_ledge_crate.tscn is described in host_world_query_test.gd (the wall's
## face at x = 4.9, the ledge's top at 0.3, the low crate's top at 0.5). gap_ceiling_step.tscn,
## floor top at y = 0 over x and z in -20..20:
## - two walls 0.2 m thick (x 4.9..5.1), 3 m high, over z -5..-0.1 and 0.1..5: a gap 0.2 m wide;
## - a low ceiling 0.2 m thick, its underside at 1.95, over x -10..-4, z -3..3;
## - under it a step with its top at 0.3 over x -10..-8, z -3..3.

const LEVEL := "res://tests/fixtures/levels/wall_ledge_crate.tscn"
const GAPS := "res://tests/fixtures/levels/gap_ceiling_step.tscn"
## The fixture mode's capsule radius (FixtureModes.player_rules).
const RADIUS := 0.4
## A thrown item's radius (#302's provisional value).
const ITEM := 0.15
## cast_motion's safe fraction stops the sphere a little short of contact.
const SHORT := 0.01


func test_with_no_level_a_sweep_reaches_its_end() -> void:
	var query := HostWorldQuery.new(RADIUS)
	var to := Vector3(10, 1.6, 0)
	assert_vector(query.sweep(Vector3(0, 1.6, 0), to, ITEM)).is_equal(to)


func test_a_sweep_with_nothing_in_the_way_reaches_its_end() -> void:
	var query := _level(LEVEL)
	var to := Vector3(3, 1.6, -2)
	assert_vector(query.sweep(Vector3(0, 1.6, 0), to, ITEM)).is_equal(to)
	# Coordinates where from + (to - from) need not round back to `to` in single precision:
	# the answer is `to` itself, bit for bit (FlightTicks tells a clear segment by it).
	var off := Vector3(1.33, 1.7, -2.9)
	assert_vector(query.sweep(Vector3(0.3, 1.3, 0.1), off, ITEM)).is_equal(off)


func test_a_sweep_stops_before_the_wall_the_ledge_and_the_crate() -> void:
	var query := _level(LEVEL)
	_assert_stops(query.sweep(Vector3(0, 1.6, 0), Vector3(8, 1.6, 0), ITEM), Vector3(4.75, 1.6, 0))
	_assert_stops(query.sweep(Vector3(-8, 2, 0), Vector3(-8, -1, 0), ITEM), Vector3(-8, 0.45, 0))
	_assert_stops(query.sweep(Vector3(0, 0.3, 3), Vector3(0, 0.3, 8), ITEM), Vector3(0, 0.3, 5.35))
	# Over the crate's top.
	var over := Vector3(0, 0.7, 8)
	assert_vector(query.sweep(Vector3(0, 0.7, 3), over, ITEM)).is_equal(over)


func test_a_sweep_through_a_gap_narrower_than_the_sphere_stops() -> void:
	var query := _level(GAPS)
	var from := Vector3(0, 1.6, 0)
	var to := Vector3(8, 1.6, 0)
	# A ray slips through the gap; the sphere does not.
	assert_bool(query.line_of_sight(from, to)).is_true()
	# Its centre on the gap's middle line, the sphere touches the walls' edges (z = +-0.1).
	var contact := 4.9 - sqrt(ITEM * ITEM - 0.1 * 0.1)
	_assert_stops(query.sweep(from, to, ITEM), Vector3(contact, 1.6, 0))
	assert_vector(query.sweep(from, to, 0.05)).is_equal(to)


func test_a_sweep_that_starts_in_the_ceiling_answers_its_start() -> void:
	var query := _level(GAPS)
	var inside := Vector3(-6, 2, 0)
	assert_vector(query.sweep(inside, Vector3(-6, 1, 2), ITEM)).is_equal(inside)
	# Touching its underside from below: also the start, whichever way it goes.
	var touching := Vector3(-6, 1.85, 0)
	assert_vector(query.sweep(touching, Vector3(-6, 1, 0), ITEM)).is_equal(touching)
	var clear := Vector3(-6, 1.6, 0)
	assert_vector(query.sweep(clear, Vector3(-5, 1.6, 2), ITEM)).is_equal(Vector3(-5, 1.6, 2))


## THROW_RADIUS_MARGIN_M: Jolt finds a sphere that touches a box clear and one 1 mm into it
## overlapping, so a capsule pressed against a wall or a ceiling leaves the sphere at its eye, of
## the largest radius the margin allows, clear of it.
func test_the_largest_sphere_at_a_pressed_capsule_s_eye_starts_clear() -> void:
	var rules := FixtureItemModes.basic().player_rules
	var above_eye := rules.capsule_height_m - rules.eye_height_m
	var margin := WorldQuery.THROW_RADIUS_MARGIN_M
	var walls := _level(LEVEL)
	var eye := Vector3(4.9 - rules.capsule_radius_m, rules.eye_height_m, 0)
	var away := Vector3(0, rules.eye_height_m, 0)
	assert_vector(walls.sweep(eye, away, rules.capsule_radius_m - margin)).is_equal(away)
	assert_vector(walls.sweep(eye, away, rules.capsule_radius_m)).is_equal(away)
	assert_vector(walls.sweep(eye, away, rules.capsule_radius_m + 0.001)).is_equal(eye)
	var ceiling := _level(GAPS)
	var under := Vector3(-6, 1.95 - above_eye, 0)
	var on := Vector3(-5, under.y, 2)
	assert_vector(ceiling.sweep(under, on, above_eye - margin)).is_equal(on)
	assert_vector(ceiling.sweep(under, on, above_eye + 0.001)).is_equal(under)


## TE7's accepted case: a thrower at the step's foot with its capsule's rim on the step (held at the
## step's height by its footprint, E10 (b)) has the eye Items.eye_of raises to the step's top plus
## the eye height, and the sphere there starts in the low ceiling. One on the ground beside it,
## clear of the step, throws.
func test_the_eye_items_gives_a_thrower_at_the_step_s_foot_answers_its_start() -> void:
	var mode := FixtureItemModes.basic()
	var rules := mode.player_rules
	var query := HostWorldQuery.new(rules.capsule_radius_m)
	var scene := (load(GAPS) as PackedScene).instantiate()
	query.add_level(LevelWorld.from_scene(scene, FixtureModes.LOBBY))
	query.add_level(LevelWorld.from_scene(scene, FixtureModes.MAP))
	scene.free()
	var game := FixtureItemModes.in_round(mode, [1, 2], query)
	FixtureItemModes.stand(game, 1, Vector3(-7.7, 0.3, 0))
	FixtureItemModes.stand(game, 2, Vector3(-7, 0, 0))
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.world = query
	var eye := Items.eye_of(ctx, game.state.player(1))
	assert_float(eye.y).is_equal_approx(0.3 + rules.eye_height_m, 1e-3)
	var radius := (
		minf(rules.capsule_radius_m, rules.capsule_height_m - rules.eye_height_m)
		- WorldQuery.THROW_RADIUS_MARGIN_M
	)
	var ahead := Vector3(-5, eye.y, 0)
	assert_vector(query.sweep(eye, ahead, radius)).is_equal(eye)
	var beside := Items.eye_of(ctx, game.state.player(2))
	assert_float(beside.y).is_equal_approx(rules.eye_height_m, 1e-3)
	var beside_ahead := Vector3(-5, beside.y, 0)
	assert_vector(query.sweep(beside, beside_ahead, radius)).is_equal(beside_ahead)
	assert_array(Array(game.diagnostics)).is_empty()


## Stopped short of `contact` (the sphere's centre at contact) along the sweep, by less than SHORT.
func _assert_stops(at: Vector3, contact: Vector3) -> void:
	assert_vector(at).is_equal_approx(contact, Vector3.ONE * SHORT)


func _level(path: String) -> HostWorldQuery:
	var query := HostWorldQuery.new(RADIUS)
	query.add_level(LevelWorld.build(path))
	query.use_level(path)
	return query
