extends GdUnitTestSuite
## PhotoFrame (the photo ADR §2.3): the pyramid from the lens toward the aim, with the vertical
## field of view, the aspect and the range; the near limit and the four edges.

## A lens at eye height looking along +X: 90 degrees vertical, aspect 2, range 10. At depth d the
## frame reaches d up and down and 2d to each side.
const LENS := Vector3(0, 1.6, 0)
const AIM := Vector3(5, 1.6, 0)
const FOV := 90.0
const ASPECT := 2.0
const RANGE := 10.0
const EPS := 0.01


func test_the_centre_and_points_just_inside_each_edge_are_in_the_frame() -> void:
	var frame := _frame()
	assert_bool(frame.contains(AIM)).is_true()
	# At depth 4: up and down 4, sideways 8 (+Z is the picture's right when looking along +X).
	assert_bool(frame.contains(LENS + Vector3(4, 4 - EPS, 0))).is_true()
	assert_bool(frame.contains(LENS + Vector3(4, -4 + EPS, 0))).is_true()
	assert_bool(frame.contains(LENS + Vector3(4, 0, 8 - EPS))).is_true()
	assert_bool(frame.contains(LENS + Vector3(4, 0, -8 + EPS))).is_true()


func test_points_just_outside_each_edge_are_not() -> void:
	var frame := _frame()
	assert_bool(frame.contains(LENS + Vector3(4, 4 + EPS, 0))).is_false()
	assert_bool(frame.contains(LENS + Vector3(4, -4 - EPS, 0))).is_false()
	assert_bool(frame.contains(LENS + Vector3(4, 0, 8 + EPS))).is_false()
	assert_bool(frame.contains(LENS + Vector3(4, 0, -8 - EPS))).is_false()


func test_nearer_than_the_near_limit_beyond_the_range_or_behind_the_lens_is_not() -> void:
	var frame := _frame()
	assert_bool(frame.contains(LENS + Vector3(PhotoFrame.NEAR_M - EPS, 0, 0))).is_false()
	assert_bool(frame.contains(LENS + Vector3(PhotoFrame.NEAR_M + EPS, 0, 0))).is_true()
	assert_bool(frame.contains(LENS + Vector3(RANGE - EPS, 0, 0))).is_true()
	assert_bool(frame.contains(LENS + Vector3(RANGE + EPS, 0, 0))).is_false()
	assert_bool(frame.contains(LENS + Vector3(-4, 0, 0))).is_false()


func test_the_frame_turns_with_the_aim() -> void:
	# Looking along -Z now: a point ahead on -Z counts, one on +X at the same distance does not.
	var frame := PhotoFrame.between(LENS, LENS + Vector3(0, 0, -5), FOV, ASPECT, RANGE)
	assert_bool(frame.contains(LENS + Vector3(0, 0, -4))).is_true()
	assert_bool(frame.contains(LENS + Vector3(4, 0, 0))).is_false()
	# Sideways is X now: 2d to each side at depth d.
	assert_bool(frame.contains(LENS + Vector3(8 - EPS, 0, -4))).is_true()
	assert_bool(frame.contains(LENS + Vector3(8 + EPS, 0, -4))).is_false()


func test_an_aim_straight_above_still_makes_a_frame() -> void:
	var frame := PhotoFrame.between(LENS, LENS + Vector3.UP * 5, FOV, ASPECT, RANGE)
	assert_bool(frame.contains(LENS + Vector3.UP * 4)).is_true()
	assert_bool(frame.contains(LENS + Vector3.DOWN * 4)).is_false()


func _frame() -> PhotoFrame:
	return PhotoFrame.between(LENS, AIM, FOV, ASPECT, RANGE)
