extends GdUnitTestSuite
## The base mode's knife launch on its maps (728e, #849; the knockdown rework's KD10 (A), KD11,
## KE1 (b), KE12, §9), in the host's world of each map (LevelWorld and HostWorldQuery, as
## house_markers_test.gd builds them, and HostBodies), since bots play the House only on a flat
## fake floor (ARCHITECTURE §9.7). A match of content/modes/base_mode.tres's own data in the melee
## fixture (FixtureBaseModeWithMelee: the shipped mode with the Round's strike and knives, which
## the M8 slice took out of the shipped match, #1497), its knife
## (content/items/knife.tres: launch_mps and launch_up_mps, placeholders "not a decision") and its
## PlayerRules (the crouching capsule, the rest, the longest motion), with the host's loop written
## out as host_bodies_test.gd writes it: three physics frames per host tick, the bodies' reports at
## the head of each tick's batch, LaunchBody and StopBody carried out as HostSession does.
##
## On the House, a knife knockdown in each of eight directions from a sample of places players
## stand (the yard, the terrace, the balcony, the top of the external stairs: house_throws.gd's
## areas, read from the level's floors, not fixed points) rests the body on a floor within the
## longest motion, upright all the way, with a crouching player's capsule at the rest point clear
## of the level (KD11). Each case waits real physics frames and asserts where the body may rest,
## never an exact point (KE1 (b)): the motion is the physics engine's. Four places launch at once,
## one attacker and one target each (peers 1 to 8): the bodies pass through each other (KE13).
##
## On the greybox, which motion_maps leaves out (KE12), the same knife starts no host body: a
## knockdown there is today's, its events step for step those of a knife with no launch.

const HouseThrows := preload("res://tests/integration/levels/house_throws.gd")
const HOUSE := "res://levels/house/house.tscn"
const GREYBOX := "res://levels/greybox/greybox.tscn"
## 60 physics frames a second, 20 host ticks.
const FRAMES_PER_TICK := 3
## The attacker stands this far behind its target, against the launch (within the knife's reach).
const BEHIND_M := 0.5
## The launch directions: every 360 / DIRECTIONS degrees.
const DIRECTIONS := 8
## The places, in peer order: place k's attacker is peer 2k + 1, its target 2k + 2.
const PLACES: Array[String] = ["yard", "terrace", "balcony", "top of the stairs"]
## Physics frames the greybox check runs the host's loop after the knockdown (ten host ticks).
const GREYBOX_FRAMES := 30

var _mode: GameMode
var _rules: PlayerRules
var _strike: Strike
var _world: HostWorldQuery
var _house: LevelWorld
var _layouts: Dictionary[String, LevelLayout]
var _game: Match
var _seen := 0
## Per target peer: whether its body ever turned, and the physics frames its motion lasted.
var _turned: Dictionary[int, bool] = {}
var _frames: Dictionary[int, int] = {}
## The knife's own numbers, put back after a test that zeroes them.
var _launch_mps := 0.0
var _launch_up_mps := 0.0


func before() -> void:
	_mode = FixtureBaseModeWithMelee.mode()
	_rules = _mode.player_rules
	_strike = _mode.find_item_kind(&"knife").actions[0].effects[0] as Strike
	_launch_mps = _strike.launch_mps
	_launch_up_mps = _strike.launch_up_mps
	_world = HostWorldQuery.new(_rules.capsule_radius_m, _rules.crouch_height_m)
	for path: String in MarkerReader.level_paths_of(_mode):
		var level := LevelWorld.build(path)
		if path == HOUSE:
			_house = level
		_world.add_level(level)
	var levels := MarkerReader.read_levels(_mode, _world)
	_layouts = levels.layouts
	assert_array(Array(_world.errors)).is_empty()
	assert_array(Array(levels.errors)).is_empty()


func after_test() -> void:
	_strike.launch_mps = _launch_mps
	_strike.launch_up_mps = _launch_up_mps
	if _world != null:
		_world.bodies.clear()
	_game = null


func after() -> void:
	_world = null
	_house = null
	_mode = null
	_rules = null
	_strike = null


func test_the_knife_launches_and_the_base_mode_moves_bodies_on_the_house_alone() -> void:
	assert_float(_strike.launch_mps).is_greater(0.0)
	assert_float(_strike.launch_up_mps).is_greater(0.0)
	assert_array(Array(_rules.motion_maps)).contains_exactly([HOUSE])
	assert_bool(_mode.maps.has(GREYBOX)).is_true()


func test_every_place_has_a_floor_to_launch_from() -> void:
	var places := _places()
	for place: String in PLACES:
		(
			assert_bool(places.has(place))
			. override_failure_message("no floor found for %s" % place)
			. is_true()
		)


func test_a_knife_launch_in_each_direction_from_each_place_rests_where_a_body_may() -> void:
	var places := _places()
	assert_int(places.size()).is_equal(PLACES.size())
	if places.size() != PLACES.size():
		return
	for k in DIRECTIONS:
		var angle := TAU * k / DIRECTIONS
		var towards := Vector3(sin(angle), 0.0, cos(angle))
		_house_round()
		var targets: Array[int] = []
		for i in PLACES.size():
			var at: Vector3 = places[PLACES[i]]
			_arm(2 * i + 1, at - towards * BEHIND_M)
			FixtureItemModes.stand(_game, 2 * i + 2, at)
			targets.append(2 * i + 2)
		_knock_down_all(targets, towards)
		for i in targets.size():
			var target := targets[i]
			var at: Vector3 = places[PLACES[i]]
			assert_object(_game.state.player(target).motion).is_not_null()
			# The launch is the knife's (KE9): away from the attacker, and up.
			var launched := _game.state.player(target).velocity
			assert_float(launched.y).is_equal_approx(_strike.launch_up_mps, 0.001)
			var flat := Vector3(launched.x, 0.0, launched.z)
			assert_vector(flat).is_equal_approx(towards * _strike.launch_mps, Vector3.ONE * 0.001)
			assert_vector(_game.state.player(target).position).is_equal(at)
		await _until_rest(targets)
		for i in targets.size():
			_assert_rests_well(targets[i], "%s, launched towards %s" % [PLACES[i], towards])


func test_on_the_greybox_the_knife_starts_no_host_body_and_knocks_down_as_today() -> void:
	var launching := await _greybox_knockdown()
	assert_array(_directives(launching)).is_empty()
	_strike.launch_mps = 0.0
	_strike.launch_up_mps = 0.0
	var still := await _greybox_knockdown()
	# Step for step a knockdown with no launch: the same events on the same ticks to the same peers.
	assert_array(launching).is_equal(still)


## The sample of places players stand, each a floor point of house_throws.gd's areas on the House:
## the yard (the first spot around the house), the terrace and the balcony (the middle spot of
## each on its own floor: the terrace's columns under the balcony give the balcony's floor too),
## and the top of the external stairs (its highest step a body stands on: the art's flight is one
## sloped collider, and on its last step, the balcony's edge, a body stands on the balcony's floor
## (HostWorldQuery.stand_floor_below), above the flight's top, so the highest step where a body
## stands lower than that). Each column gives every floor in it, the basement's included.
func _places() -> Dictionary[String, Vector3]:
	_world.use_level(HOUSE)
	var spots := HouseThrows.spots(_world, _rules.eye_height_m)
	var found: Dictionary[String, Vector3] = {}
	var around: Array = spots["around_the_house"]
	if not around.is_empty():
		found["yard"] = around[0]
	# The terrace on the ground floor (0 m, house_throws.gd), the balcony on the top of its columns.
	var levels := {"terrace": 0.0, "balcony": _highest(spots["balcony"])}
	for area: String in levels:
		var level: float = levels[area]
		var on_floor := (spots[area] as Array).filter(
			func(spot: Vector3) -> bool: return absf(spot.y - level) < 0.5
		)
		if not on_floor.is_empty():
			found[area] = on_floor[int(on_floor.size() / 2.0)]
	var stairs: Array = spots["external_stairs"]
	var highest := _highest(stairs)
	var on_flight := stairs.filter(func(step: Vector3) -> bool: return _stands_at(step).y < highest)
	var top := _highest(on_flight)
	for step: Vector3 in on_flight:
		if step.y == top:
			found["top of the stairs"] = step
	return found


## The floor a body standing at `at` stands on (_assert_rests_well's reading).
func _stands_at(at: Vector3) -> Vector3:
	return _world.stand_floor_below(Items.lifted(at + Vector3.UP * _rules.capsule_radius_m))


## The highest floor among `spots` (-INF for none).
func _highest(spots: Array) -> float:
	var top := -INF
	for spot: Vector3 in spots:
		top = maxf(top, spot.y)
	return top


## A base-mode match on `map` in the host's world, peers 1 to 8 joined, readied and loaded into the
## round (content_modes_test.gd's _base_round, in the host's world).
func _house_round(map: String = HOUSE) -> void:
	_turned.clear()
	_frames.clear()
	_game = Match.new(_mode, 7, _world, _layouts)
	assert_array(Array(_game.refusals)).is_empty()
	_game.state.map = map
	_game.keep_history = true
	_game.start(0)
	var peers: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
	for peer: int in peers:
		FixtureBaseMode.join(_game, peer)
	for peer: int in peers:
		FixtureBaseMode.ready(_game, peer)
	for i in 1000:
		if _game.phase_id() == &"loading":
			break
		FixtureModes.run_ticks(_game, 1)
	for peer: int in peers:
		FixtureBaseMode.load_ack(_game, peer)
	for i in 1000:
		if _game.phase_id() == &"round":
			break
		FixtureModes.run_ticks(_game, 1)
	assert_str(_game.phase_id()).is_equal("round")
	assert_str(_world.level_path()).is_equal(map)
	_seen = _game.emitted().size()


## Each target's attacker (the peer before it), armed, strikes it twice along `towards`: the
## knife's two blows knock it down.
func _knock_down_all(targets: Array[int], towards: Vector3) -> void:
	for target: int in targets:
		FixtureCombatModes.use(_game, target - 1, towards)
	FixtureModes.run_ticks(_game, FixtureCombatModes.COOLDOWN_TICKS)
	for target: int in targets:
		FixtureCombatModes.use(_game, target - 1, towards)
	_carry_out()
	for target: int in targets:
		(
			assert_int(_game.state.player(target).life)
			. override_failure_message("peer %d not knocked down" % target)
			. is_equal(PlayerState.Life.DOWNED)
		)
	for target: int in targets:
		assert_array(FixtureModes.rejections(_game, target - 1)).is_empty()


## The host's loop until every target's motion ends: physics frames, and every FRAMES_PER_TICK of
## them a host tick headed by the bodies' reports.
func _until_rest(targets: Array[int]) -> void:
	var limit := _frame_limit() + 10 * FRAMES_PER_TICK
	var frame := 0
	while frame < limit and not _all_at_rest(targets):
		await get_tree().physics_frame
		frame += 1
		for target: int in targets:
			_watch(target)
		if frame % FRAMES_PER_TICK == 0:
			_host_tick()


func _all_at_rest(targets: Array[int]) -> bool:
	for target: int in targets:
		if _game.state.player(target).motion != null:
			return false
	return true


## One host tick: the reports, stamped with it, then the tick, then the directives.
func _host_tick() -> void:
	var at_tick := _game.ticked_through() + 1
	for report: MatchCommand in _world.bodies.reports():
		report.tick = at_tick
		_game.apply(report)
	_carry_out()
	_game.tick(at_tick)
	_carry_out()


## LaunchBody and StopBody emitted since the last call, carried out as HostSession does.
func _carry_out() -> void:
	var emitted := _game.emitted()
	for i in range(_seen, emitted.size()):
		var event := emitted[i].event
		if event is LaunchBodyEvent:
			var launch := event as LaunchBodyEvent
			_world.bodies.launch(launch.peer, launch.epoch, launch.origin, launch.velocity)
		elif event is StopBodyEvent:
			_world.bodies.stop((event as StopBodyEvent).peer)
	_seen = emitted.size()


func _watch(peer: int) -> void:
	if not _world.bodies.peers().has(peer):
		return
	_frames[peer] = _frames.get(peer, 0) + 1
	if not _world.bodies.transform_of(peer).basis.is_equal_approx(Basis.IDENTITY):
		_turned[peer] = true


## The physics frames of the mode's longest motion, and one host tick more.
func _frame_limit() -> int:
	return int(_rules.longest_motion_s * Ticks.RATE) * FRAMES_PER_TICK + FRAMES_PER_TICK


## Where a body may rest (host_bodies_test.gd's checks on the House): still, its host body freed,
## within the longest motion, upright all the way, on the standing floor under its capsule (no
## fallback: the match logged no error), and with a crouching player's capsule there (lifted by
## Items.SURFACE_CLEARANCE_M and narrowed by it: touching a floor, a wall or an underside is not a
## hit) clear of the level (KD11).
func _assert_rests_well(peer: int, label: String) -> void:
	var downed := _game.state.player(peer)
	var at := downed.position
	var where := "%s: rests at %s" % [label, at]
	assert_object(downed.motion).override_failure_message(where).is_null()
	assert_vector(downed.velocity).override_failure_message(where).is_equal(Vector3.ZERO)
	assert_bool(_world.bodies.peers().has(peer)).override_failure_message(where).is_false()
	assert_int(_frames.get(peer, 0)).override_failure_message(where).is_less_equal(_frame_limit())
	assert_bool(_turned.get(peer, false)).override_failure_message(where + ", turned").is_false()
	var floor_at := _world.stand_floor_below(
		Items.lifted(at + Vector3.UP * _rules.capsule_radius_m)
	)
	assert_vector(floor_at).override_failure_message(where + ", not on a floor").is_equal_approx(
		at, Vector3.ONE * 0.01
	)
	var capsule := CapsuleShape3D.new()
	capsule.radius = _rules.capsule_radius_m - Items.SURFACE_CLEARANCE_M
	capsule.height = _rules.crouch_height_m
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	var centre := at + Vector3.UP * (_rules.crouch_height_m / 2.0 + Items.SURFACE_CLEARANCE_M)
	query.transform = Transform3D(Basis.IDENTITY, centre)
	var hits := _house.space_state().intersect_shape(query, 1)
	(
		assert_array(hits)
		. override_failure_message(where + ", a crouching player does not fit there")
		. is_empty()
	)
	assert_array(Array(_game.diagnostics)).override_failure_message(where).is_empty()


## A base-mode round on the greybox where peer 1 knocks peer 2 down with the knife's two blows,
## with the host's loop run for the longest motion: what it emitted from the first blow on, each as
## its tick, its name, its fields and its recipients; and no host body ever started.
func _greybox_knockdown() -> Array[String]:
	_house_round(GREYBOX)
	var at := _game.state.player(2).position
	var towards := Vector3(1, 0, 0)
	_arm(1, at - towards * BEHIND_M)
	var from := _game.emitted().size()
	_knock_down_all([2], towards)
	assert_object(_game.state.player(2).motion).is_null()
	assert_vector(_game.state.player(2).velocity).is_equal(Vector3.ZERO)
	assert_vector(_game.state.player(2).position).is_equal_approx(at, Vector3.ONE * 0.01)
	for frame in GREYBOX_FRAMES:
		await get_tree().physics_frame
		assert_array(_world.bodies.peers()).is_empty()
		if frame % FRAMES_PER_TICK == 0:
			_host_tick()
	var found: Array[String] = []
	var emitted := _game.emitted()
	for i in range(from, emitted.size()):
		var each := emitted[i]
		found.append(
			(
				"%d %s %s %s"
				% [each.tick, each.event.event_name(), each.event.to_dict(), each.recipients]
			)
		)
	assert_array(Array(_game.diagnostics)).is_empty()
	return found


## The directives (LaunchBody, StopBody) among `events`, each named by its event.
func _directives(events: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for each: String in events:
		if each.contains("LaunchBody") or each.contains("StopBody"):
			found.append(each)
	return found


## Puts `peer` at `at` with a knife in its hand, straight into the match state: a pick-up's sight
## from the eye to an item on the balcony's floor is not what these tests check.
func _arm(peer: int, at: Vector3) -> void:
	FixtureItemModes.stand(_game, peer, at)
	var knife := FixtureItemModes.lay(_game, &"knife", at)
	knife.where = ItemState.Where.HAND
	knife.holder = peer
	_game.state.player(peer).held_item = knife.id
