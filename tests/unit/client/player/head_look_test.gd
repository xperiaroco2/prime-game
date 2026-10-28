extends GdUnitTestSuite
## HeadLook (#1334): body_follow's 45-degree dead zone with the wrap at +-180 degrees, and the
## head's clamps (yaw +-70, pitch up 40, down 35 degrees).

const ZONE := PI * 0.25


func _deg(degrees: float) -> float:
	return deg_to_rad(degrees)


func _follow(body_deg: float, aim_deg: float) -> float:
	return rad_to_deg(HeadLook.body_follow(_deg(body_deg), _deg(aim_deg), ZONE))


func test_inside_the_zone_the_body_keeps_its_yaw() -> void:
	assert_float(_follow(10.0, 10.0)).is_equal_approx(10.0, 0.001)
	assert_float(_follow(10.0, 54.0)).is_equal_approx(10.0, 0.001)
	assert_float(_follow(10.0, -34.0)).is_equal_approx(10.0, 0.001)
	assert_float(_follow(10.0, 55.0)).is_equal_approx(10.0, 0.001)


func test_beyond_the_zone_the_aim_stays_on_its_edge() -> void:
	assert_float(_follow(10.0, 60.0)).is_equal_approx(15.0, 0.001)
	assert_float(_follow(10.0, -50.0)).is_equal_approx(-5.0, 0.001)
	assert_float(_follow(0.0, 120.0)).is_equal_approx(75.0, 0.001)


func test_the_wrap_at_180_degrees() -> void:
	# 20 degrees apart across the wrap: kept.
	assert_float(_follow(170.0, -170.0)).is_equal_approx(170.0, 0.001)
	assert_float(_follow(-170.0, 170.0)).is_equal_approx(-170.0, 0.001)
	# 70 degrees apart across the wrap: the short way round, the aim on the edge.
	assert_float(_follow(170.0, -120.0)).is_equal_approx(-165.0, 0.001)
	assert_float(_follow(-170.0, 120.0)).is_equal_approx(165.0, 0.001)
	# The result stays within -180..180.
	var turned := _follow(179.0, -130.0)
	assert_float(turned).is_between(-180.0, 180.0)
	assert_float(turned).is_equal_approx(-175.0, 0.001)


func test_a_shake_inside_the_zone_never_turns_the_body() -> void:
	var body := _deg(30.0)
	for i: int in 100:
		var aim := _deg(30.0) + _deg(40.0) * sin(i * 0.5)
		body = HeadLook.body_follow(body, aim, ZONE)
	assert_float(rad_to_deg(body)).is_equal_approx(30.0, 0.001)


func test_a_broken_number_keeps_the_body() -> void:
	assert_float(HeadLook.body_follow(0.5, NAN, ZONE)).is_equal(0.5)
	assert_float(HeadLook.body_follow(0.5, INF, ZONE)).is_equal(0.5)


func test_the_clamps() -> void:
	assert_float(rad_to_deg(HeadLook.clamped(_deg(90.0), 0.0).x)).is_equal_approx(70.0, 0.001)
	assert_float(rad_to_deg(HeadLook.clamped(_deg(-90.0), 0.0).x)).is_equal_approx(-70.0, 0.001)
	assert_float(rad_to_deg(HeadLook.clamped(_deg(60.0), 0.0).x)).is_equal_approx(60.0, 0.001)
	assert_float(rad_to_deg(HeadLook.clamped(0.0, _deg(80.0)).y)).is_equal_approx(40.0, 0.001)
	assert_float(rad_to_deg(HeadLook.clamped(0.0, _deg(-80.0)).y)).is_equal_approx(-35.0, 0.001)
	assert_float(rad_to_deg(HeadLook.clamped(0.0, _deg(-20.0)).y)).is_equal_approx(-20.0, 0.001)
	assert_that(HeadLook.clamped(NAN, INF)).is_equal(Vector2.ZERO)


func test_the_turn_looks_where_the_aim_points() -> void:
	# The body faces -Z: a yaw to the left turns the look toward -X, a pitch up toward +Y.
	var left := HeadLook.turn_of(_deg(60.0), 0.0) * Vector3.FORWARD
	assert_float(left.x).is_less(-0.8)
	var up := HeadLook.turn_of(0.0, _deg(30.0)) * Vector3.FORWARD
	assert_float(up.y).is_equal_approx(0.5, 0.001)
	# Past the clamp the turn stops at it.
	var far := HeadLook.turn_of(_deg(170.0), 0.0) * Vector3.FORWARD
	assert_float(far.angle_to(Vector3.FORWARD)).is_equal_approx(_deg(70.0), 0.001)
