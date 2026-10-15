extends GdUnitTestSuite
## BodyViews (ARCHITECTURE §4.7 Others, E26): a body appears where Died put it, the own player's
## too, and is removed at its player's Respawned or PlayerLeft; each is in SightHider's group.
## With no knocked-down ragdoll to keep (no AvatarViews here), a body is a fresh ragdoll lying at
## rest along -Z, grey, on no layer, with the dark cross over its point (KD7 (a)); the ragdoll
## AvatarViews hands over at a death is life_ragdoll_network_test's. With a character (#522) the
## fresh ragdoll is its grey skeleton, every bone on no layer.

const OWN := 2
const OTHER := 5
const Fixture := preload("res://tests/integration/client/player/character_fixture.gd")

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


func test_a_body_is_a_grey_ragdoll_lying_at_rest_on_no_layer_with_the_cross() -> void:
	var rules := FixtureModes.player_rules()
	var at := Vector3(3, 0, -4)
	_model.fold(&"Died", {"peer": OTHER, "position": at})
	await get_tree().physics_frame
	await get_tree().physics_frame
	var view := _views.view_of(OTHER)
	var ragdoll := view.get_node(^"Ragdoll") as RagdollView
	assert_object(ragdoll).is_not_null()
	assert_bool(ragdoll.is_dead()).is_true()
	assert_object(ragdoll.colour()).is_equal(LifeLooks.BODY_COLOUR)
	assert_int(ragdoll.collision_layer).is_equal(0)
	assert_bool(ragdoll.top_level).is_true()
	assert_vector(ragdoll.held_point()).is_equal(at)
	# Lying along -Z over the point (no floor here: the spring holds it up, sagging a little).
	assert_float(absf(ragdoll.global_basis.y.normalized().z)).is_greater(0.99)
	assert_float(ragdoll.global_position.distance_to(ragdoll.lying_centre())).is_less(0.3)
	var cross := view.get_node(^"Cross") as Node3D
	assert_int(cross.get_child_count()).is_equal(2)
	var bar := cross.get_child(0) as MeshInstance3D
	var dark := (bar.mesh as BoxMesh).material as StandardMaterial3D
	assert_object(dark.albedo_color).is_equal(LifeLooks.CROSS_COLOUR)
	assert_float(bar.global_position.y).is_greater(rules.capsule_radius_m * 2.0)
	assert_vector(Vector3(bar.global_position.x, 0, bar.global_position.z)).is_equal(at)
	_model.fold(&"Respawned", {"peer": OTHER, "position": Vector3.ZERO})
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(_views.count()).is_equal(0)


func test_with_a_character_a_body_is_its_grey_skeleton_lying_on_no_layer() -> void:
	_views.character = CharacterSet.from_scene(Fixture.scene(), Fixture.ragdoll())
	var at := Vector3(3, 0, -4)
	_model.fold(&"Died", {"peer": OTHER, "position": at})
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ragdoll := _views.view_of(OTHER).get_node(^"Ragdoll") as RagdollView
	assert_object(ragdoll.rig()).is_not_null()
	assert_bool(ragdoll.is_dead()).is_true()
	assert_object(ragdoll.rig().tint()).is_equal(LifeLooks.BODY_COLOUR)
	assert_int(ragdoll.collision_layer).is_equal(0)
	assert_int(ragdoll.bones().size()).is_greater(0)
	for bone: PhysicalBone3D in ragdoll.bones():
		assert_int(bone.collision_layer).is_equal(0)
	for i: int in 30:
		await get_tree().physics_frame
	# No floor here: the spring holds it up, sagging by g / SPRING_K.
	var pelvis := ragdoll.pelvis().global_position
	assert_float(pelvis.distance_to(ragdoll.lying_centre())).is_less(0.3)
