extends GdUnitTestSuite
## Where the ears are (Ears.point(); E40, the M5 ADR §1.5 and §3 item 4): the own eye while living,
## the own body's head where it lies while downed (never the downed camera above and behind it),
## a spectated living target's eye, a downed target's head where it lies, and with no target the
## own body's head.

const OWN_FEET := Vector3(2, 0, 3)
const EYE := Vector3(2, 1.6, 3)
const TARGET_FEET := Vector3(-4, 0, 1)

var _rules: PlayerRules


func before() -> void:
	_rules = FixtureModes.player_rules()


func test_the_living_hear_from_their_own_eye() -> void:
	var at := _point(ClientModel.Life.ALIVE, 0, ClientModel.Life.ALIVE)
	assert_vector(at).is_equal(EYE)


func test_the_downed_hear_from_their_head_where_they_lie() -> void:
	var at := _point(ClientModel.Life.DOWNED, 0, ClientModel.Life.ALIVE)
	# Near the floor, at the lying capsule's axis height: not the eye, not above the body.
	assert_float(at.y).is_equal_approx(_rules.capsule_radius_m, 1e-4)
	var lying_reach := _rules.capsule_height_m * 0.5
	assert_float(Vector2(at.x, at.z).distance_to(Vector2(OWN_FEET.x, OWN_FEET.z))).is_less_equal(
		lying_reach
	)
	assert_vector(at).is_equal_approx(Ears.lying_head(_feet(OWN_FEET), _rules), Vector3.ONE * 1e-5)


func test_the_head_lies_where_the_lying_capsule_puts_the_eyes_and_turns_with_the_body() -> void:
	var feet := Transform3D(Basis(Vector3.UP, PI * 0.5), OWN_FEET)
	var head := Ears.lying_head(feet, _rules)
	# The standing eye, carried through the standing and lying mesh poses (LifeLooks).
	var in_mesh := Vector3(0, _rules.eye_height_m - _rules.capsule_height_m * 0.5, 0)
	var want := feet * (LifeLooks.lying(_rules) * in_mesh)
	assert_vector(head).is_equal_approx(want, Vector3.ONE * 1e-5)
	assert_float(head.distance_to(OWN_FEET)).is_greater(0.1)
	var unturned := Ears.lying_head(_feet(OWN_FEET), _rules)
	assert_float(head.distance_to(unturned)).is_greater(0.1)


func test_the_dead_hear_from_a_living_targets_eye() -> void:
	var at := _point(ClientModel.Life.DEAD, 7, ClientModel.Life.ALIVE)
	assert_vector(at).is_equal(TARGET_FEET + Vector3.UP * _rules.eye_height_m)


func test_the_dead_hear_from_a_downed_targets_head() -> void:
	var at := _point(ClientModel.Life.DEAD, 7, ClientModel.Life.DOWNED)
	assert_vector(at).is_equal_approx(
		Ears.lying_head(_feet(TARGET_FEET), _rules), Vector3.ONE * 1e-5
	)


func test_the_dead_without_a_target_hear_from_their_own_body() -> void:
	var at := _point(ClientModel.Life.DEAD, 0, ClientModel.Life.ALIVE)
	assert_vector(at).is_equal_approx(Ears.lying_head(_feet(OWN_FEET), _rules), Vector3.ONE * 1e-5)
	assert_vector(_point(ClientModel.Life.LEFT, 0, ClientModel.Life.ALIVE)).is_equal(at)


func _point(own: ClientModel.Life, target: int, target_life: ClientModel.Life) -> Vector3:
	return Ears.point(own, _feet(OWN_FEET), EYE, target, target_life, _feet(TARGET_FEET), _rules)


func _feet(at: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, at)
