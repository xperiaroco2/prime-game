extends GdUnitTestSuite
## DownedCamera.clamp_eye() (the knockdown ADR's KE8, ARCHITECTURE §4.7.9): the pivot rises from
## the body's point by the standing eye height, never higher than that height above the floor below
## the point, and stops CEILING_MARGIN_M under the first hit above; NAN is no hit.

const EYE_M := 1.6


func test_at_rest_on_the_floor_the_pivot_is_the_standing_eye_over_the_point() -> void:
	var pivot := DownedCamera.clamp_eye(Vector3(2, 0.5, -3), EYE_M, 0.5, NAN)
	assert_vector(pivot).is_equal_approx(Vector3(2, 0.5 + EYE_M, -3), Vector3.ONE * 1e-5)


func test_in_flight_the_pivot_is_no_higher_than_the_eye_over_the_floor_below() -> void:
	var pivot := DownedCamera.clamp_eye(Vector3(1, 3.0, 0), EYE_M, 0.0, NAN)
	assert_vector(pivot).is_equal_approx(Vector3(1, EYE_M, 0), Vector3.ONE * 1e-5)


func test_with_no_floor_below_it_rises_by_the_eye_height() -> void:
	var pivot := DownedCamera.clamp_eye(Vector3(0, -2.0, 0), EYE_M, NAN, NAN)
	assert_float(pivot.y).is_equal_approx(-2.0 + EYE_M, 1e-5)


func test_under_a_low_ceiling_it_stops_the_margin_below_it() -> void:
	var pivot := DownedCamera.clamp_eye(Vector3(0, 0, 0), EYE_M, 0.0, 1.4)
	assert_float(pivot.y).is_equal_approx(1.4 - DownedCamera.CEILING_MARGIN_M, 1e-5)
	assert_float(DownedCamera.CEILING_MARGIN_M).is_equal_approx(0.1, 1e-6)


func test_the_lower_of_the_two_clamps_holds() -> void:
	# Flying under a ceiling higher than the eye over the floor: the floor's clamp.
	var floor_lower := DownedCamera.clamp_eye(Vector3(0, 1.0, 0), EYE_M, 0.0, 2.5)
	assert_float(floor_lower.y).is_equal_approx(EYE_M, 1e-5)
	# Under a ceiling lower than that: the ceiling's.
	var ceiling_lower := DownedCamera.clamp_eye(Vector3(0, 0.3, 0), EYE_M, 0.0, 1.5)
	assert_float(ceiling_lower.y).is_equal_approx(1.4, 1e-5)
