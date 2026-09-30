extends GdUnitTestSuite
## Ticks: seconds and amounts per second to ticks and thousandths, rounded toward zero once
## (ARCHITECTURE §3.3).


func test_seconds_to_ticks() -> void:
	assert_int(Ticks.from_seconds(5)).is_equal(100)
	assert_int(Ticks.from_seconds(0.5)).is_equal(10)
	assert_int(Ticks.from_seconds(60)).is_equal(1200)
	assert_int(Ticks.from_seconds(0)).is_equal(0)


func test_float_error_does_not_lose_a_tick() -> void:
	assert_int(Ticks.from_seconds(0.35)).is_equal(7)
	assert_int(Ticks.from_seconds(0.7)).is_equal(14)
	assert_int(Ticks.from_seconds(2.3)).is_equal(46)


func test_rounds_toward_zero() -> void:
	assert_int(Ticks.from_seconds(0.049)).is_equal(0)
	assert_int(Ticks.from_seconds(0.099)).is_equal(1)
	assert_int(Ticks.from_seconds(-0.07)).is_equal(-1)


func test_minutes_to_ticks() -> void:
	assert_int(Ticks.from_minutes(10)).is_equal(12000)
	assert_int(Ticks.from_minutes(1)).is_equal(1200)


func test_per_second_amounts_to_thousandths_per_tick() -> void:
	assert_int(Ticks.per_tick(15)).is_equal(750)
	assert_int(Ticks.per_tick(20)).is_equal(1000)
	assert_int(Ticks.per_tick(7)).is_equal(350)
	assert_int(Ticks.per_tick(0.01)).is_equal(0)
	assert_int(Ticks.per_tick(0.3)).is_equal(15)


func test_points_to_thousandths() -> void:
	assert_int(Ticks.thousandths(100)).is_equal(100000)
	assert_int(Ticks.thousandths(0.0015)).is_equal(1)
