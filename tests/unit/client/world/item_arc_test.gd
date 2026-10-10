extends GdUnitTestSuite
## ItemArc (client/world/item_arc.gd; ARCHITECTURE §4.7.25, §7.1.16; the throwing ADR's TE5 (a)):
## the drawn arc is core's ItemFlight.point() at every whole tick and the host's swept segment in
## between; the thrower's prediction builds the host's vectors from the client's copy of the
## rule, found in core's order; the stop is the arc's point above the host's rest, a short fall
## follows, and a rest not below the drawn arc ends it at once. Matches of the throw fixture mode
## (FixtureThrowModes: 10 m/s, 9.8 m/s², radius 0.15 m, 3 s) give the host's side.

const P1 := 1
const P2 := 2
const HERE := Vector3(1, 0, 2)
const AHEAD := Vector3(0, 1.8, -2.4)
const O := Vector3(0, 1.6, 0)
const V := Vector3(0, 4, -8)
const G := Vector3(0, -9.8, 0)


func test_the_arc_points_are_cores_points_at_whole_ticks() -> void:
	for n: int in 61:
		assert_bool(ItemArc.point_at(O, V, G, float(n)) == ItemFlight.point(O, V, G, n)).is_true()
	# Between two ticks the item is on the segment the host sweeps, not on point(k).
	var before := ItemFlight.point(O, V, G, 7)
	var after := ItemFlight.point(O, V, G, 8)
	assert_vector(ItemArc.point_at(O, V, G, 7.25)).is_equal_approx(
		before.lerp(after, 0.25), Vector3.ONE * 1e-5
	)
	assert_bool(ItemArc.point_at(O, V, G, 7.25) == before).is_false()


func test_the_prediction_is_the_hosts_arc_for_the_same_numbers() -> void:
	var mode := FixtureThrowModes.basic()
	var game := _round(mode)
	var item := FixtureFlightModes.holding(game, P1, HERE)
	FixtureThrowModes.throw(game, P1, AHEAD)
	var host := FixtureThrowModes.thrown_seen_by(game, P2)[0].to_dict()
	var rule := ItemArc.rule_of(mode, item.kind.id, game.state.player(P1).role)
	assert_object(rule).is_not_null()
	# The thrower's camera at the host's eye, looking along the facing it sent.
	var arc := ItemArc.predict(rule, item.id, P1, host["origin"] as Vector3, AHEAD)
	assert_bool(arc.velocity == host["velocity"]).is_true()
	assert_bool(arc.gravity == host["gravity"]).is_true()
	assert_float(arc.radius).is_equal(FixtureThrowModes.RADIUS_M)
	for n: int in 61:
		var hosts := ItemFlight.point(
			host["origin"] as Vector3, host["velocity"] as Vector3, host["gravity"] as Vector3, n
		)
		assert_bool(ItemArc.point_at(arc.origin, arc.velocity, arc.gravity, n) == hosts).is_true()


func test_rule_of_follows_cores_order() -> void:
	# The item kind's Throw rule before the role's and the mode's: a match launches at its speed.
	var mode := FixtureThrowModes.basic()
	var kinds := FixtureThrowModes.effect(6.0)
	mode.find_item_kind(&"package").actions.append(FixtureThrowModes.throw_rule(kinds))
	assert_object(ItemArc.rule_of(mode, &"package", &"")).is_same(kinds)
	var game := _round(mode)
	FixtureFlightModes.holding(game, P1, HERE)
	FixtureThrowModes.throw(game, P1, AHEAD)
	var velocity := FixtureThrowModes.thrown_seen_by(game, P1)[0].to_dict()["velocity"] as Vector3
	assert_float(velocity.length()).is_equal_approx(6.0, 1e-5)
	# Another kind falls back to the mode's rule; a role's rule comes before the mode's.
	assert_float(ItemArc.rule_of(mode, &"tool", &"").speed_mps).is_equal(10.0)
	var role := FixtureModes.role(&"thrower", &"crew", false)
	var roles := FixtureThrowModes.effect(4.0)
	role.actions.append(FixtureThrowModes.throw_rule(roles))
	mode.roles.append(role)
	assert_object(ItemArc.rule_of(mode, &"tool", &"thrower")).is_same(roles)
	assert_object(ItemArc.rule_of(mode, &"package", &"thrower")).is_same(kinds)
	# The first Throw rule decides, as in core: one without a ThrowItem throws nothing.
	mode.find_item_kind(&"tool").actions.push_front(
		FixtureModes.rule(Intents.THROW, [], [FixtureNote.of("no throw")])
	)
	assert_object(ItemArc.rule_of(mode, &"tool", &"thrower")).is_null()
	# A mode with no Throw rule (built in code: the base mode gets its rule in 37f).
	assert_object(ItemArc.rule_of(FixtureItemModes.basic(), &"package", &"")).is_null()
	assert_object(ItemArc.rule_of(null, &"package", &"")).is_null()


func test_the_stop_is_the_arc_point_above_the_hosts_rest() -> void:
	# A throw at a wall 4 m ahead: the host stops the item at the wall and drops it straight down.
	var world := FlatWorldQuery.new()
	world.add_wall(AABB(Vector3(-5, 0, -6.2), Vector3(10, 4, 0.2)))
	var game := _round(FixtureThrowModes.basic(), world)
	FixtureFlightModes.holding(game, P1, HERE)
	FixtureThrowModes.throw(game, P1, Vector3(0, 0.3, -1))
	var host := FixtureThrowModes.thrown_seen_by(game, P2)[0].to_dict()
	# The launch tick L is the next one, and FlightTicks skips it: after tick L + k, k ticks flown.
	var flown := -1
	while FixtureThrowModes.flying(game) != null and flown < 80:
		FixtureModes.run_ticks(game, 1)
		flown += 1
	var placed := game.view_of(P2).events_named(&"ItemPlaced")
	assert_array(placed).has_size(1)
	var rest := placed[0].to_dict()["position"] as Vector3
	assert_float(rest.y).is_equal(0.0)
	var o := host["origin"] as Vector3
	var v := host["velocity"] as Vector3
	var g := host["gravity"] as Vector3
	var stop := ItemArc.stop_of(o, v, g, rest, float(flown))
	# On the segment the host swept last, right above the rest.
	assert_float(stop).is_between(float(flown - 1), float(flown))
	var at := ItemArc.point_at(o, v, g, stop)
	assert_float(Vector2(at.x - rest.x, at.z - rest.z).length()).is_less(1e-3)
	assert_float(at.y).is_greater(rest.y)
	# A rest under a point the flight cannot have reached by then is no stop of it.
	assert_float(ItemArc.stop_of(o, v, g, rest, flown - 5.0)).is_equal(ItemArc.NO_STOP)


func test_the_longest_flight_stops_at_its_last_point() -> void:
	var last := ItemFlight.point(O, V, G, 60)
	var rest := Vector3(last.x, last.y - 2.0, last.z)
	assert_float(ItemArc.stop_of(O, V, G, rest, 60.0)).is_equal_approx(60.0, 1e-3)


func test_a_throw_straight_up_falls_back_to_the_rests_height() -> void:
	var up := Vector3(0, 6, 0)
	var rest := Vector3(0, 0, 0)
	# 1.6 + 6 s - 4.9 s² = 0: s = (6 + sqrt(36 + 31.36)) / 9.8.
	var seconds := (6.0 + sqrt(36.0 + 4.0 * 4.9 * 1.6)) / 9.8
	var stop := ItemArc.stop_of(O, up, G, rest, 100.0)
	assert_float(stop).is_equal_approx(seconds * Ticks.RATE, 0.01)
	# A ceiling stopped it on the way up: no later than the latest tick (and its slack).
	assert_float(ItemArc.stop_of(O, up, G, rest, 3.0)).is_equal(3.0 + ItemArc.STOP_SLACK_TICKS)
	# A rest beside a vertical throw is not below it.
	assert_float(ItemArc.stop_of(O, up, G, Vector3(1, 0, 0), 100.0)).is_equal(ItemArc.NO_STOP)


func test_a_rest_off_the_arc_ends_it_at_once() -> void:
	var arc := ItemArc.thrown(_launch(10))
	arc.n = 4.0
	# Sideways of the arc's line, and behind the thrower: neither is below the arc.
	assert_float(ItemArc.stop_of(O, V, G, Vector3(1, 0, -6), 40.0)).is_equal(ItemArc.NO_STOP)
	assert_float(ItemArc.stop_of(O, V, G, Vector3(0, 0, 2), 40.0)).is_equal(ItemArc.NO_STOP)
	arc.end_at(_placed(Vector3(1, 0, -6)), 40.0)
	assert_bool(arc.finished()).is_true()
	assert_vector(arc.position()).is_equal(Vector3(1, 0, -6))


func test_the_no_floor_fallback_at_the_throwers_feet_ends_the_drawn_arc_at_once() -> void:
	# The flight went over an edge and the item rests where the thrower stood (TD11 (a)): the
	# drawn item, already well along the arc, is not above that rest.
	var arc := ItemArc.thrown(_launch(10))
	arc.n = 6.0
	var feet := Vector3(O.x, 0, O.z)
	arc.end_at(_placed(feet), 30.0)
	assert_bool(arc.finished()).is_true()
	assert_vector(arc.position()).is_equal(feet)


func test_the_drawn_item_flies_to_the_stop_then_falls_to_the_rest() -> void:
	var arc := ItemArc.thrown(_launch(10))
	var stop_point := ItemFlight.point(O, V, G, 12)
	var rest := Vector3(stop_point.x, 0, stop_point.z)
	arc.n = 5.0
	arc.end_at(_placed(rest), 14.0)
	assert_bool(arc.finished()).is_false()
	assert_vector(arc.position()).is_equal(ItemFlight.point(O, V, G, 5))
	assert_vector(arc.position_at(12.0)).is_equal_approx(stop_point, Vector3.ONE * 1e-4)
	# Straight down, with the arc's gravity: sqrt(2h/g) seconds.
	var fall_ticks := sqrt(2.0 * stop_point.y / 9.8) * Ticks.RATE
	var middle := arc.position_at(12.0 + fall_ticks * 0.5)
	assert_float(middle.x).is_equal_approx(rest.x, 1e-4)
	assert_float(middle.z).is_equal_approx(rest.z, 1e-4)
	assert_float(middle.y).is_between(0.0, stop_point.y)
	arc.n = 12.0 + fall_ticks + 0.01
	assert_bool(arc.finished()).is_true()
	assert_vector(arc.position()).is_equal(rest)


func test_the_launch_is_not_drawn_before_its_tick() -> void:
	var arc := ItemArc.thrown(_launch(10))
	arc.n = -0.5
	assert_bool(arc.position().is_finite()).is_false()
	arc.n = 0.0
	assert_vector(arc.position()).is_equal(O)


func test_the_prediction_eases_onto_the_hosts_arc() -> void:
	var rule := FixtureThrowModes.effect()
	var arc := ItemArc.predict(rule, 3, P1, O + Vector3(0, 0.3, 0), Vector3(0, 0.5, -1))
	arc.n = 4.0
	var before := arc.position()
	var host := _launch(10)
	host["velocity"] = Vector3(0, 0.5, -1).normalized() * 10.0
	arc.adopt(host)
	assert_bool(arc.predicted).is_false()
	assert_int(arc.launch_tick).is_equal(10)
	assert_vector(arc.position()).is_equal_approx(before, Vector3.ONE * 1e-5)
	var hosts := ItemFlight.point(O, host["velocity"] as Vector3, G, 4)
	arc.ease_by(ItemArc.EASE_S * 0.5)
	assert_vector(arc.position()).is_equal_approx(before.lerp(hosts, 0.5), Vector3.ONE * 1e-5)
	arc.ease_by(ItemArc.EASE_S)
	assert_vector(arc.position()).is_equal_approx(hosts, Vector3.ONE * 1e-5)


func _round(mode: GameMode, world: WorldQuery = null) -> Match:
	var game := FixtureItemModes.in_round(mode, [P1, P2], world)
	assert_array(Array(game.diagnostics)).is_empty()
	return game


func _launch(tick: int) -> Dictionary:
	return {"item": 3, "peer": P2, "origin": O, "velocity": V, "gravity": G, "tick": tick}


func _placed(at: Vector3) -> Dictionary:
	return {"item": 3, "position": at, "cause": Items.THROWN}
