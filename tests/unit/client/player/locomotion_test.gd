extends GdUnitTestSuite
## Locomotion (#1334): the heading in the body's frame, the eight points' blend positions, the
## family switch around 100 degrees with its +-10-degree dead zone, the side and back speed caps,
## and the footstep contacts from the art table.

const SIDE := 3.0
const BACK := 2.0


func _deg(degrees: float) -> float:
	return deg_to_rad(degrees)


func test_the_heading_counts_from_the_body_positive_to_its_left() -> void:
	for yaw: float in [0.0, 1.3, -2.4]:
		for heading: float in [0.0, 0.7, -1.9, 3.0]:
			var flat := Basis(Vector3.UP, yaw + heading) * Vector3(0.0, 0.0, -3.0)
			assert_float(Locomotion.heading_of(flat, yaw)).is_equal_approx(heading, 0.0001)


func test_each_point_sits_at_its_direction() -> void:
	var expected := {
		&"Jog_Fwd": Vector2(0.0, 1.0),
		&"Jog_Fwd_Left": Vector2(-sqrt(0.5), sqrt(0.5)),
		&"Strafe_Left": Vector2(-1.0, 0.0),
		&"Jog_Fwd_Right": Vector2(sqrt(0.5), sqrt(0.5)),
		&"Strafe_Right": Vector2(1.0, 0.0),
		&"Jog_Bwd": Vector2(0.0, -1.0),
		&"Jog_Bwd_Left": Vector2(-sqrt(0.5), -sqrt(0.5)),
		&"Jog_Bwd_Right": Vector2(sqrt(0.5), -sqrt(0.5)),
	}
	assert_int(Locomotion.POINTS.size()).is_equal(8)
	for point: Dictionary in Locomotion.POINTS:
		var at := Locomotion.blend_position(_deg(point["heading_deg"] as float))
		var want: Vector2 = expected[point["clip"]]
		assert_float(at.distance_to(want)).is_less(0.0001)
		# Its family is the side of the switch its heading falls on.
		var back := absf(point["heading_deg"] as float) > Locomotion.SWITCH_DEG
		var family := Locomotion.BACK if back else Locomotion.FRONT
		assert_str(String(point["family"] as StringName)).is_equal(String(family))


func test_the_blend_position_is_a_direction_never_a_speed() -> void:
	for heading: float in [0.0, 0.4, -2.0, PI]:
		assert_float(Locomotion.blend_position(heading).length()).is_equal_approx(1.0, 0.0001)


func test_the_families_split_the_points() -> void:
	var front: Array[StringName] = []
	for point: Dictionary in Locomotion.points_of(Locomotion.FRONT):
		front.append(point["clip"] as StringName)
	assert_array(front).contains_exactly_in_any_order(
		[&"Jog_Fwd", &"Jog_Fwd_Left", &"Jog_Fwd_Right", &"Strafe_Left", &"Strafe_Right"]
	)
	assert_int(Locomotion.points_of(Locomotion.BACK).size()).is_equal(3)
	# The art MVP set lacks the four diagonals: the rig adds them only when present.
	assert_array(Locomotion.optional_clips()).contains_exactly_in_any_order(
		[&"Jog_Fwd_Left", &"Jog_Fwd_Right", &"Jog_Bwd_Left", &"Jog_Bwd_Right"]
	)
	for clip: StringName in Locomotion.optional_clips():
		assert_bool(AvatarClips.all_clips().has(clip)).is_false()


func test_the_family_switch_and_its_dead_zone() -> void:
	for side: float in [1.0, -1.0]:
		# From the front: still front up to 110 degrees, back beyond it.
		assert_str(String(Locomotion.family_of(_deg(99.0 * side), false))).is_equal("Front")
		assert_str(String(Locomotion.family_of(_deg(109.0 * side), false))).is_equal("Front")
		assert_str(String(Locomotion.family_of(_deg(111.0 * side), false))).is_equal("Back")
		# From the back: still back down to 90 degrees, front below it.
		assert_str(String(Locomotion.family_of(_deg(101.0 * side), true))).is_equal("Back")
		assert_str(String(Locomotion.family_of(_deg(91.0 * side), true))).is_equal("Back")
		assert_str(String(Locomotion.family_of(_deg(89.0 * side), true))).is_equal("Front")
		assert_str(String(Locomotion.family_of(PI * side, false))).is_equal("Back")
		assert_str(String(Locomotion.family_of(0.0, true))).is_equal("Front")


func test_a_heading_wobbling_about_the_switch_never_flickers() -> void:
	for start_back: bool in [false, true]:
		var back := start_back
		for i: int in 200:
			var heading := _deg(100.0 + 5.0 * sin(i * 0.7))
			back = Locomotion.family_of(heading, back) == Locomotion.BACK
			assert_bool(back).is_equal(start_back)


func test_the_caps() -> void:
	var front := Locomotion.FRONT
	var back := Locomotion.BACK
	# Straight ahead: no cap.
	assert_float(Locomotion.speed_cap(0.0, front, SIDE, BACK)).is_equal(INF)
	# Sideways: 3.0, either side; a front diagonal's sideways part is 3.0 (4.24 m/s in all).
	for side: float in [1.0, -1.0]:
		assert_float(Locomotion.speed_cap(_deg(90.0 * side), front, SIDE, BACK)).is_equal_approx(
			SIDE, 0.0001
		)
		assert_float(Locomotion.speed_cap(_deg(45.0 * side), front, SIDE, BACK)).is_equal_approx(
			SIDE / sin(_deg(45.0)), 0.0001
		)
		# Backward and the back diagonals: 2.0.
		for heading: float in [135.0, 180.0, 115.0]:
			var cap := Locomotion.speed_cap(_deg(heading * side), back, SIDE, BACK)
			assert_float(cap).is_equal_approx(BACK, 0.0001)
	# A cap of 0 is none.
	assert_float(Locomotion.speed_cap(PI, back, 0.0, 0.0)).is_equal(INF)
	assert_float(Locomotion.speed_cap(_deg(90.0), front, 0.0, BACK)).is_equal(INF)


func test_the_contacts_are_the_tables_times_over_the_rate() -> void:
	# At rate r the two steps of a cycle fall the contact times / r apart.
	var cases := {
		&"Jog_Fwd": [0.458, 0.459],
		&"Strafe_Left": [0.458, 0.459],
		&"Jog_Bwd": [0.292, 0.291],
		&"Sprint_Fwd": [0.375, 0.292],
		&"Walk": [0.667, 0.666],
	}
	for clip: StringName in cases:
		var phases := Locomotion.contacts(clip)
		var cycle := Locomotion.cycle_s(clip)
		assert_int(phases.size()).is_equal(2)
		for rate: float in [1.0, 2.398]:
			var first := (phases[1] - phases[0]) * cycle / rate
			var second := (1.0 - phases[1] + phases[0]) * cycle / rate
			assert_float(first).is_equal_approx((cases[clip][0] as float) / rate, 0.002)
			assert_float(second).is_equal_approx((cases[clip][1] as float) / rate, 0.002)
	# An idle has none.
	assert_int(Locomotion.contacts(&"Idle").size()).is_equal(0)
	assert_float(Locomotion.cycle_s(&"Idle")).is_equal(0.0)
