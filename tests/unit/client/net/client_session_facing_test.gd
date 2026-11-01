extends GdUnitTestSuite
## ClientSession and the host's facing for this client (#1522, ARCHITECTURE §4.2): a placement's
## Correction with a facing emits `faced` before `corrected`, and the next claims say it; a
## Correction with none (a refused claim, a knockdown, a revive) leaves the look alone; Welcome's
## facing is welcome_facing, for Game to turn the joiner once its player exists.

const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
## One client tick at 20 Hz, in microseconds.
const TICK_USEC := 50000

var _harness: Harness
var _heard: Array[String] = []


func before_test() -> void:
	_harness = Harness.new()
	_heard.clear()


func after_test() -> void:
	_harness.close()


func test_a_placement_s_facing_is_faced_before_corrected_and_claimed() -> void:
	_harness.welcome()
	_listen()
	var placed := Vector3(7, 0, 7)
	_harness.send(CorrectionEvent.new(_harness.peer, 2, placed, Vector3.ZERO, Vector3.BACK))
	_harness.pump(TICK_USEC)
	assert_array(_heard).is_equal(["faced %s" % Vector3.BACK, "corrected %s" % placed])
	var claim := _harness.claims()[-1].fields
	assert_int(claim["epoch"] as int).is_equal(2)
	assert_vector(claim["facing"] as Vector3).is_equal(Vector3.BACK)


func test_a_correction_with_no_facing_turns_nothing() -> void:
	_harness.welcome()
	_harness.session.set_motion(Vector3(1, 0, 2), Vector3.ZERO, Vector3.LEFT, false, false, true)
	_listen()
	var refused := Vector3(1, 0, 2)
	_harness.send(CorrectionEvent.new(_harness.peer, 2, refused, Vector3.ZERO))
	_harness.pump(TICK_USEC)
	assert_array(_heard).is_equal(["corrected %s" % refused])
	assert_vector(_harness.claims()[-1].fields["facing"] as Vector3).is_equal(Vector3.LEFT)


func test_welcome_s_facing_is_kept_for_the_joiner_and_claimed() -> void:
	_listen()
	_harness.welcome(&"lobby", 1, Vector3.BACK)
	assert_vector(_harness.session.welcome_facing).is_equal(Vector3.BACK)
	assert_array(_heard).is_empty()
	_harness.pump(TICK_USEC)
	assert_vector(_harness.claims()[-1].fields["facing"] as Vector3).is_equal(Vector3.BACK)


func test_a_welcome_with_no_facing_keeps_the_default_look() -> void:
	_harness.welcome()
	assert_vector(_harness.session.welcome_facing).is_equal(Vector3.ZERO)
	_harness.pump(TICK_USEC)
	assert_vector(_harness.claims()[-1].fields["facing"] as Vector3).is_equal(Vector3.FORWARD)


func _listen() -> void:
	_harness.session.faced.connect(
		func(facing: Vector3) -> void: _heard.append("faced %s" % facing)
	)
	_harness.session.corrected.connect(
		func(position: Vector3, _velocity: Vector3) -> void:
			_heard.append("corrected %s" % position)
	)
