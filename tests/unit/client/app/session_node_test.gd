extends GdUnitTestSuite
## SessionNode's clock (ARCHITECTURE §4.6 and §4.7): the session's time is the physics steps run, a
## claim every third step at 60 Hz; the physics rate is a multiple of the client tick rate; and
## after a hitch longer than Godot's catch-up the step count jumps forward to the real clock by
## whole client ticks right after a claim, so the client tick never trails real time for good (the
## netcode review of PR #154).

const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")

var _harness: Harness
var _node: SessionNode
## The real clock the node reads, in microseconds.
var _real := 0


func before_test() -> void:
	_harness = Harness.new()
	_harness.welcome()
	_node = SessionNode.new(_harness.session)
	_node.real_clock = _real_clock
	# The session's clock started at the harness's: the node's steps start there too.
	_node.set("_steps", ceili(_harness.now * Engine.physics_ticks_per_second / 1000000.0))
	_real = _node.now_usec()


func after_test() -> void:
	_node.free()
	_harness.close()


func test_the_physics_rate_is_a_multiple_of_the_client_tick_rate() -> void:
	assert_int(Engine.physics_ticks_per_second % Ticks.RATE).is_equal(0)
	assert_int(SessionNode.steps_per_tick()).is_equal(3)


func test_n_steps_are_n_physics_frames_of_time_and_a_claim_every_third() -> void:
	var start := _node.steps()
	var claims_before := _harness.sent_named(Intents.MOVE_CLAIM).size()
	var claimed_at: Array[int] = []
	for i: int in 60:
		_step()
		var made := _harness.sent_named(Intents.MOVE_CLAIM).size()
		if made > claims_before + claimed_at.size():
			claimed_at.append(i)
	var steps_run := _node.steps() - start
	assert_int(steps_run).is_equal(60)
	var expected := _node.steps() * 1000000 / Engine.physics_ticks_per_second
	assert_int(_node.now_usec()).is_equal(expected)
	assert_int(claimed_at.size()).is_equal(20)
	for i: int in range(1, claimed_at.size()):
		assert_int(claimed_at[i] - claimed_at[i - 1]).is_equal(3)


func test_a_short_lag_behind_the_real_clock_is_kept() -> void:
	# Two steps behind (Godot's catch-up deals with it): no jump.
	_step()
	_real += 2 * SessionNode._usec_of(1)
	var steps_before := _node.steps()
	for i: int in 6:
		_step()
	assert_int(_node.steps() - steps_before).is_equal(6)


func test_after_a_long_hitch_the_steps_jump_to_the_real_clock_by_whole_ticks() -> void:
	for i: int in 6:
		_step()
	# A 500 ms hitch Godot does not catch up: 30 steps of real time with no physics step.
	_real += 500000
	var ticks_before := _claim_ticks()
	var steps_before := _node.steps()
	for i: int in 6:
		_step()
	# The jump came right after a claim, by whole client ticks, and left less than a tick behind.
	var jumped := _node.steps() - steps_before - 6
	assert_int(jumped).is_greater_equal(27)
	assert_int(jumped % SessionNode.steps_per_tick()).is_equal(0)
	assert_float(_real_steps() - _node.steps()).is_less(SessionNode.CATCH_UP_STEPS)
	# One claim covers the hitch's ticks with one tick's travel; then one tick per claim again.
	for i: int in 9:
		_step()
	var ticks: Array[int] = []
	ticks.assign(_claim_ticks().slice(ticks_before.size()))
	assert_int(ticks[0] - ticks_before[-1]).is_equal(1)
	assert_int(ticks[1] - ticks[0]).is_greater_equal(10)
	for i: int in range(2, ticks.size()):
		assert_int(ticks[i] - ticks[i - 1]).is_equal(1)
	# The client tick is real time's again.
	var real_tick := _harness.session.client_tick(_real)
	assert_int(absi(ticks[-1] - real_tick)).is_less_equal(1)


## One physics step: the real clock moves a step's time, the node steps the session, the host
## reads what it sent.
func _step() -> void:
	_real += SessionNode._usec_of(1)
	_node._physics_process(1.0 / Engine.physics_ticks_per_second)
	_harness.host.poll()


func _real_steps() -> float:
	var start: int = _node.get("_real_start")
	return (_real - start) * Engine.physics_ticks_per_second / 1000000.0


func _claim_ticks() -> Array[int]:
	var ticks: Array[int] = []
	for claim: WireMessage in _harness.sent_named(Intents.MOVE_CLAIM):
		ticks.append(claim.fields["client_tick"] as int)
	return ticks


func _real_clock() -> int:
	return _real
