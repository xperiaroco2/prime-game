extends GdUnitTestSuite
## The pinball's ball between snapshots (#1400, ARCHITECTURE §4.7.63): linear between two samples
## that show it, held past the newest, hidden by a sample without it only from that sample's tick,
## snapped across a long jump, stale ticks ignored, old samples dropped.

var _track: PinballBallTrack


func before_test() -> void:
	_track = PinballBallTrack.new()


func test_nothing_is_drawn_before_the_first_sample() -> void:
	assert_object(_track.at(10.0)).is_null()
	_track.add(10, true, Vector3(0.1, 0.03, 0.2))
	assert_object(_track.at(9.5)).is_null()


func test_the_ball_is_linear_between_two_samples() -> void:
	_track.add(10, true, Vector3(0.0, 0.03, 0.4))
	_track.add(11, true, Vector3(0.2, 0.03, 0.0))
	assert_vector(_track.at(10.5) as Vector3).is_equal_approx(
		Vector3(0.1, 0.03, 0.2), Vector3.ONE * 1e-5
	)
	assert_vector(_track.at(10.0) as Vector3).is_equal_approx(
		Vector3(0.0, 0.03, 0.4), Vector3.ONE * 1e-5
	)


func test_the_ball_holds_at_the_newest_sample() -> void:
	_track.add(10, true, Vector3(0.0, 0.03, 0.4))
	_track.add(11, true, Vector3(0.2, 0.03, 0.0))
	assert_vector(_track.at(14.0) as Vector3).is_equal(Vector3(0.2, 0.03, 0.0))


func test_an_absent_sample_hides_the_ball_only_from_its_tick() -> void:
	_track.add(10, true, Vector3(0.0, 0.03, 0.5))
	_track.add(11, false, Vector3.ZERO)
	# Before the absent sample's tick the ball still shows where it was (it drains in sight).
	assert_vector(_track.at(10.6) as Vector3).is_equal(Vector3(0.0, 0.03, 0.5))
	assert_object(_track.at(11.0)).is_null()
	assert_object(_track.at(12.0)).is_null()


func test_a_jump_longer_than_snap_m_holds_the_older_place_until_the_newer_tick() -> void:
	_track.add(10, true, Vector3(0.0, 0.03, -0.6))
	_track.add(11, true, Vector3(0.0, 0.03, 0.5))
	assert_vector(_track.at(10.9) as Vector3).is_equal(Vector3(0.0, 0.03, -0.6))
	assert_vector(_track.at(11.0) as Vector3).is_equal(Vector3(0.0, 0.03, 0.5))


func test_a_stale_or_repeated_tick_is_ignored() -> void:
	assert_bool(_track.add(10, true, Vector3(0.1, 0.03, 0.0))).is_true()
	assert_bool(_track.add(10, false, Vector3.ZERO)).is_false()
	assert_bool(_track.add(9, true, Vector3(0.3, 0.03, 0.0))).is_false()
	assert_int(_track.newest()).is_equal(10)
	assert_vector(_track.at(12.0) as Vector3).is_equal(Vector3(0.1, 0.03, 0.0))


func test_samples_older_than_keep_ticks_are_dropped() -> void:
	_track.add(1, true, Vector3(0.1, 0.03, 0.0))
	_track.add(2 + PinballBallTrack.KEEP_TICKS, true, Vector3(0.2, 0.03, 0.0))
	# The first is gone: before the kept one nothing is known.
	assert_object(_track.at(1.5)).is_null()


func test_clear_forgets_every_sample() -> void:
	_track.add(10, true, Vector3(0.1, 0.03, 0.0))
	_track.clear()
	assert_object(_track.at(10.0)).is_null()
	assert_int(_track.newest()).is_equal(-1)
