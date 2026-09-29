extends GdUnitTestSuite
## Spike (#14): the host's crude movement check accepts honest walking and rejects teleports,
## speed-ups, positions outside the room and moves from before a correction.

const V := SpikeMoveCheck.Verdict
const PEER := 7
const FRAME := 1.0 / 60.0

var _check: SpikeMoveCheck


func before_test() -> void:
	_check = SpikeMoveCheck.new()
	_check.place(PEER, Vector3(0, 1, 0))


## Walks along x at speed for seconds, reporting every report_every seconds; returns the verdicts.
func _walk(speed: float, seconds: float, report_every: float) -> Array[SpikeMoveCheck.Verdict]:
	var verdicts: Array[SpikeMoveCheck.Verdict] = []
	var pos := _check.position_of(PEER)
	var since := 0.0
	var t := 0.0
	while t < seconds:
		t += FRAME
		since += FRAME
		_check.advance(FRAME)
		pos.x += speed * FRAME
		if since >= report_every:
			since = 0.0
			verdicts.append(_check.check(PEER, _check.epoch_of(PEER), pos))
	return verdicts


func test_accepts_walking_at_top_speed() -> void:
	var verdicts := _walk(_check.max_speed, 1.2, 0.05)
	assert_int(verdicts.size()).is_greater(10)
	assert_int(verdicts.count(V.ACCEPTED)).is_equal(verdicts.size())


func test_accepts_a_burst_after_a_pause() -> void:
	# Packets bunched up: nothing for 0.3 s, then the whole distance at once.
	for i in 18:
		_check.advance(FRAME)
	var ahead := Vector3(_check.max_speed * 0.3, 1, 0)
	assert_int(_check.check(PEER, 1, ahead)).is_equal(V.ACCEPTED)


func test_accepts_the_moves_queued_during_a_host_hitch() -> void:
	# The host froze for 1.2 s while the client walked on, reporting every 0.05 s; then one long
	# frame and all 24 queued reports at once.
	_check.advance(1.2)
	var pos := _check.position_of(PEER)
	var accepted := 0
	for i in 24:
		pos.x += _check.max_speed * 0.05
		if _check.check(PEER, 1, pos) == V.ACCEPTED:
			accepted += 1
	assert_int(accepted).is_equal(24)


func test_the_limit_is_max_speed_times_slack() -> void:
	var limit := _check.max_speed * _check.slack
	var huge := AABB(Vector3(-1000, -10, -1000), Vector3(2000, 20, 2000))
	_check.bounds = huge
	var under := _walk(limit * 0.95, 8.0, 0.05)
	assert_int(under.count(V.ACCEPTED)).is_equal(under.size())
	before_test()
	_check.bounds = huge
	assert_bool(_walk(limit * 1.1, 8.0, 0.05).has(V.SPEED)).is_true()


func test_rejects_sustained_double_speed() -> void:
	var verdicts := _walk(_check.max_speed * 2.0, 1.2, 0.05)
	assert_bool(verdicts.has(V.SPEED)).is_true()


func test_rejects_a_teleport_even_with_a_full_budget() -> void:
	for i in 120:
		_check.advance(FRAME)
	var far := Vector3(_check.teleport_distance + 0.1, 1, 0)
	assert_int(_check.check(PEER, 1, far)).is_equal(V.TELEPORT)
	assert_vector(_check.position_of(PEER)).is_equal(Vector3(0, 1, 0))


func test_rejects_out_of_bounds() -> void:
	_check.advance(0.5)
	assert_int(_check.check(PEER, 1, Vector3(0, 5, 0))).is_equal(V.BOUNDS)


func test_falling_does_not_spend_budget() -> void:
	assert_int(_check.check(PEER, 1, Vector3(0, 0.2, 0))).is_equal(V.ACCEPTED)


func test_moves_from_before_a_correction_are_stale() -> void:
	var epoch := _check.place(PEER, Vector3(3, 1, 0))
	assert_int(epoch).is_equal(2)
	_check.advance(0.1)
	assert_int(_check.check(PEER, 1, Vector3(3.1, 1, 0))).is_equal(V.STALE)
	assert_int(_check.check(PEER, 2, Vector3(3.1, 1, 0))).is_equal(V.ACCEPTED)
