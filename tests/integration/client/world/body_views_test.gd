extends GdUnitTestSuite
## BodyViews (ARCHITECTURE §4.7 Others, E26): a body appears where Died put it, the own player's
## too, and is removed at its player's Respawned or PlayerLeft; each is in SightHider's group.

const OWN := 2
const OTHER := 5

var _model: ClientModel
var _views: BodyViews


func before_test() -> void:
	_model = ClientModel.new(FixtureBaseMode.mode())
	_model.own_peer = OWN
	_views = BodyViews.new()
	_views.model = _model
	_views.rules = FixtureModes.player_rules()
	add_child(_views)


func after_test() -> void:
	_views.free()


func test_bodies_appear_at_a_death_and_go_at_a_respawn_or_a_leave() -> void:
	_model.fold(&"Died", {"peer": OTHER, "position": Vector3(3, 0, -4)})
	_model.fold(&"Died", {"peer": OWN, "position": Vector3(-1, 0, 2)})
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(_views.count()).is_equal(2)
	var other := _views.view_of(OTHER)
	assert_vector(other.global_position).is_equal(Vector3(3, 0, -4))
	assert_bool(other.is_in_group(SightHider.GROUP)).is_true()
	var point: Vector3 = other.call(&"sight_point")
	assert_float(point.y).is_equal_approx(FixtureModes.player_rules().capsule_radius_m, 1e-4)
	_model.fold(&"Respawned", {"peer": OWN, "position": Vector3.ZERO})
	_model.fold(&"PlayerLeft", {"peer": OTHER})
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(_views.count()).is_equal(0)
