extends GdUnitTestSuite
## PinballTable on the engine's physics (#1399; ARCHITECTURE §7.1.22): the greybox scene runs
## headless in its own World3D, stepped on real physics frames (60 a second). The game is a
## Pinball.Machine played by hand as core/ would (BallLaunched puts the ball in play, BallLost takes
## it out), so each test reads the reports the table makes: an idle table builds nothing and
## reports nothing; a launch with the flippers idle ends in a BallLost; a held flipper turns up in
## two frames and throws a ball resting on it up the table; a touched target scores once per touch;
## a ball outside the walls or still is lost; a new game or no game frees the ball; the scene's
## target ids are the shipped UsePinball's. A quicker spec (a short launch delay and stuck time)
## keeps the runs short; its physics numbers are the shipped ones.

const SHIPPED_STATION := "res://content/stations/pinball.tres"

var _played: Pinball.Machine
var _table: PinballTable
var _reports: Array[MatchCommand] = []


func before_test() -> void:
	_played = Pinball.Machine.new()
	_played.serial = 1
	_played.player = 2
	_played.balls_left = 3
	var spec := (load(PinballTable.SPEC) as PinballTableSpec).duplicate() as PinballTableSpec
	spec.launch_delay_s = 0.05
	spec.stuck_s = 0.5
	_table = PinballTable.new(PinballTable.SCENE, spec)
	_reports.clear()


func after_test() -> void:
	_table = null


func test_an_idle_table_reads_nothing_and_reports_nothing() -> void:
	_played.player = -1
	await _frames(10)
	assert_bool(_table.is_active()).is_false()
	assert_bool(_table.has_ball()).is_false()
	assert_array(_reports).is_empty()
	_table.step(null, _delta())
	assert_array(_table.reports()).is_empty()


func test_a_launch_with_idle_flippers_ends_in_a_lost_ball() -> void:
	await _frames(6)
	assert_bool(_table.is_active()).is_true()
	assert_array(_table.errors).is_empty()
	assert_str(String(_reports[0].kind)).is_equal(String(Intents.BALL_LAUNCHED))
	assert_int(_reports[0].get_int("game")).is_equal(1)
	assert_bool(_played.in_play).is_true()
	assert_bool(await _until(func() -> bool: return not _played.in_play, 600)).is_true()
	var kinds := _kinds()
	assert_str(str(kinds.back())).is_equal(String(Intents.BALL_LOST))
	assert_int(kinds.count(Intents.BALL_LAUNCHED)).is_equal(1)
	assert_int(kinds.count(Intents.BALL_LOST)).is_equal(1)
	assert_bool(kinds.has(Intents.BALL_MOVED)).is_true()
	for report: MatchCommand in _reports:
		assert_int(report.get_int("game")).is_equal(1)
		if report.kind == Intents.TARGET_HIT:
			assert_array(_shipped_ids()).contains([StringName(report.get_string("target"))])
	# The next ball after the delay.
	assert_bool(await _until(func() -> bool: return _played.in_play, 30)).is_true()


func test_a_held_flipper_turns_up_in_two_frames_and_throws_the_ball() -> void:
	await _frames(1)
	var swing := deg_to_rad(_table.spec().flipper_swing_deg)
	# On the left flipper, halfway along it, resting.
	var on_flipper := Vector3(-0.075, 0.03, 0.43)
	_table.place_ball(on_flipper, Vector3.ZERO)
	_played.left = true
	await _frames(2)
	assert_float(_table.flipper_angle(0)).is_equal_approx(swing, 0.001)
	assert_float(_table.flipper_angle(1)).is_equal(0.0)
	var fastest := 0.0
	for _i in 10:
		await _frames(1)
		fastest = minf(fastest, _table.ball_velocity().z)
	assert_float(fastest).is_less(-0.5)
	_played.left = false
	await _frames(2)
	assert_float(_table.flipper_angle(0)).is_equal(0.0)


# The right flipper's rest mirrors the left one's: it turns the other way to throw the ball up.
func test_a_held_right_flipper_throws_the_ball_up_the_table() -> void:
	await _frames(1)
	var swing := deg_to_rad(_table.spec().flipper_swing_deg)
	# On the right flipper, halfway along it, resting.
	_table.place_ball(Vector3(0.075, 0.03, 0.43), Vector3.ZERO)
	_played.right = true
	await _frames(2)
	assert_float(_table.flipper_angle(1)).is_equal_approx(swing, 0.001)
	assert_float(_table.flipper_angle(0)).is_equal(0.0)
	var fastest := 0.0
	for _i in 10:
		await _frames(1)
		fastest = minf(fastest, _table.ball_velocity().z)
	assert_float(fastest).is_less(-0.5)


func test_a_ball_with_no_flipper_held_falls_off_the_flipper() -> void:
	await _frames(1)
	_table.place_ball(Vector3(-0.075, 0.03, 0.43), Vector3.ZERO)
	await _frames(12)
	assert_float(_table.ball_velocity().z).is_greater_equal(0.0)


func test_a_touched_target_scores_once_per_touch_and_kicks() -> void:
	await _frames(1)
	_reports.clear()
	# Straight at the bumper (radius 0.04 at x -0.1, z -0.25) from below.
	_table.place_ball(Vector3(-0.1, 0.03, -0.1), Vector3(0, 0, -1.0))
	await _frames(20)
	var hits := _hits()
	assert_array(hits).contains_exactly([&"bumper"])
	assert_float(_table.ball_velocity().z).is_greater(0.0)


func test_a_ball_outside_the_walls_or_still_is_lost() -> void:
	await _frames(6)
	assert_bool(_played.in_play).is_true()
	_table.place_ball(Vector3(1.0, 0.03, 0.0), Vector3.ZERO)
	await _frames(2)
	assert_bool(_played.in_play).is_false()
	assert_bool(_table.has_ball()).is_false()
	_reports.clear()
	# Still in a corner (the top wall and the left wall), no flipper held: lost after stuck_s.
	_table.spec().slope_mps2 = 0.0
	_played.in_play = true
	_table.place_ball(Vector3(-0.2, 0.03, -0.3), Vector3.ZERO)
	assert_bool(await _until(func() -> bool: return not _played.in_play, 60)).is_true()
	assert_int(_kinds().count(Intents.BALL_LOST)).is_equal(1)


func test_a_full_batch_drops_hits_but_never_a_loss() -> void:
	await _frames(6)
	assert_bool(_played.in_play).is_true()
	for _i in PinballTable.MOST_PENDING + 1:
		_table._report(Intents.TARGET_HIT, {"game": _played.serial, "target": "bumper"})
	_table.place_ball(Vector3(1.0, 0.03, 0.0), Vector3.ZERO)
	_reports.clear()
	await _frames(1)
	assert_int(_hits().size()).is_equal(PinballTable.MOST_PENDING)
	assert_int(_kinds().count(Intents.BALL_LOST)).is_equal(1)
	assert_bool(_played.in_play).is_false()


func test_a_new_game_or_no_game_frees_the_ball() -> void:
	await _frames(6)
	assert_bool(_table.has_ball()).is_true()
	_played.serial = 2
	_played.in_play = false
	_reports.clear()
	_table.step(_played, _delta())
	assert_bool(_table.has_ball()).is_false()
	assert_array(_table.reports()).is_empty()
	await _frames(6)
	assert_int(_reports[0].get_int("game")).is_equal(2)
	_played.player = -1
	await _frames(1)
	assert_bool(_table.has_ball()).is_false()
	assert_bool(_table.is_active()).is_false()


func test_the_scenes_target_ids_are_the_shipped_ones() -> void:
	await _frames(1)
	var ids := _table.target_ids()
	ids.sort()
	var shipped := _shipped_ids()
	shipped.sort()
	assert_array(ids).is_equal(shipped)


## `count` physics frames: each steps the table and takes its reports, which change `_played` as
## core/ would.
func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame
		_step()


func _until(done: Callable, most: int) -> bool:
	for _i in most:
		if done.call():
			return true
		await get_tree().physics_frame
		_step()
	return done.call()


func _step() -> void:
	_table.step(_played, _delta())
	for report: MatchCommand in _table.reports():
		_reports.append(report)
		if report.get_int("game") != _played.serial:
			continue
		if report.kind == Intents.BALL_LAUNCHED and not _played.in_play:
			_played.in_play = true
		elif report.kind == Intents.BALL_LOST and _played.in_play:
			_played.in_play = false
			_played.balls_left -= 1


func _kinds() -> Array[StringName]:
	var kinds: Array[StringName] = []
	for report: MatchCommand in _reports:
		kinds.append(report.kind)
	return kinds


func _hits() -> Array[StringName]:
	var hits: Array[StringName] = []
	for report: MatchCommand in _reports:
		if report.kind == Intents.TARGET_HIT:
			hits.append(StringName(report.get_string("target")))
	return hits


func _delta() -> float:
	return 1.0 / Engine.physics_ticks_per_second


func _shipped_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var kind := load(SHIPPED_STATION) as StationKind
	for rule: Rule in kind.actions:
		for effect: RuleEffect in rule.effects:
			if effect is UsePinball:
				for target: PinballTarget in (effect as UsePinball).targets:
					ids.append(target.id)
	return ids
