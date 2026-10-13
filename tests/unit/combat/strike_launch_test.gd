extends GdUnitTestSuite
## Strike's launch (the knockdown rework's KD2, KE9; ARCHITECTURE §9.4, #847): launch_mps away from
## the attacker horizontally, from foot to foot, along the zone's direction where they coincide,
## plus launch_up_mps up; 0 launches nothing; both bounded (placeholders, "not a decision"). What a
## launch does to a knockdown: tests/unit/life/body_motion_test.gd.


func test_the_launch_points_away_from_the_attacker_horizontally_plus_up() -> void:
	var strike := _strike(4.0, 2.0)
	var attacker := _at(1, Vector3(1, 0, 1))
	# The target stands higher and diagonally ahead: only the horizontal direction counts.
	var target := _at(2, Vector3(4, 1.5, 5))
	var launch := strike.launch_of(attacker, target, Vector2(0, 1))
	assert_vector(launch).is_equal_approx(Vector3(2.4, 2.0, 3.2), Vector3.ONE * 0.0001)


func test_a_target_on_the_attackers_spot_flies_along_the_zones_direction() -> void:
	var strike := _strike(3.0, 1.0)
	var attacker := _at(1, Vector3(2, 0, 2))
	var target := _at(2, Vector3(2, 0.5, 2))
	assert_vector(strike.launch_of(attacker, target, Vector2(1, 0))).is_equal(Vector3(3, 1, 0))
	# With no direction either, the launch is upwards only.
	assert_vector(strike.launch_of(attacker, target, Vector2.ZERO)).is_equal(Vector3(0, 1, 0))


func test_zero_launches_nothing() -> void:
	var strike := _strike(0.0, 0.0)
	var launch := strike.launch_of(_at(1, Vector3.ZERO), _at(2, Vector3(0, 0, 1)), Vector2(0, 1))
	assert_vector(launch).is_equal(Vector3.ZERO)


func test_the_launch_numbers_are_bounded() -> void:
	var mode := FixtureCombatModes.basic()
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
	var strike := mode.find_item_kind(&"knife").actions[0].effects[0] as Strike
	strike.launch_mps = 20.5
	strike.launch_up_mps = 10.5
	var errors := ";".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("Strike launch_mps is 20.5, outside 0 to 20")
	assert_str(errors).contains("Strike launch_up_mps is 10.5, outside 0 to 10")
	strike.launch_mps = -0.5
	strike.launch_up_mps = -0.5
	errors = ";".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("Strike launch_mps is -0.5, outside 0 to 20")
	assert_str(errors).contains("Strike launch_up_mps is -0.5, outside 0 to 10")
	strike.launch_mps = 20.0
	strike.launch_up_mps = 10.0
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


func _strike(launch_mps: float, launch_up_mps: float) -> Strike:
	var strike := FixtureCombatModes.strike(30.0, 1.5, 50)
	strike.launch_mps = launch_mps
	strike.launch_up_mps = launch_up_mps
	return strike


func _at(peer: int, position: Vector3) -> PlayerState:
	var player := PlayerState.new(peer, "p%d" % peer)
	player.position = position
	return player
