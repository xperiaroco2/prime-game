extends GdUnitTestSuite
## The downed camera under a low ceiling (#958): a player downed or killed crouched where the
## standing capsule finds no room keeps the DownedCamera's pivot, and SightHider's cast origin, at
## or below the crouched eye; in the open both stay at the standing eye. Real physics steps (Jolt,
## headless) on the fixture level `crouch_room.tscn`: a slab whose underside is 1.4 m above the
## floor, between the crouched 1.2 m and the standing 1.8 m of FixtureModes' rules (eyes 1.0 m and
## 1.6 m), spanning x -9.5 to -6.5 and z -1 to 3.

const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")
const CROUCH_ROOM := "res://tests/fixtures/client/crouch_room.tscn"
## Under the middle of the slab, and in the open beside it.
const UNDER := Vector3(-8.0, 0.0, 1.0)
const OPEN := Vector3(-8.0, 0.0, 6.0)
const EPSILON := 0.001

var _rules := FixtureModes.player_rules()
var _world: PlayerTestWorld
var _harness: Harness
var _model: ClientModel
var _life: LifeView


func before_test() -> void:
	_world = PlayerTestWorld.new()
	add_child(_world)
	_world.add_child((load(CROUCH_ROOM) as PackedScene).instantiate())
	_harness = Harness.new()
	_harness.welcome(&"round")
	_model = _harness.session.model
	var avatars: AvatarViews = auto_free(AvatarViews.new())
	_life = LifeView.new()
	_life.setup(_harness.session, _harness.mode, avatars)
	_world.add_child(_life)


func after_test() -> void:
	_harness.close()
	_world.free()


func test_downed_crouched_under_the_slab_the_pivot_stays_at_the_crouched_eye() -> void:
	var player := await _crouched_player(UNDER)
	_harness.send(KnockedDownEvent.new(_model.own_peer, UNDER))
	_harness.pump()
	player.life = ClientModel.Life.DOWNED
	await _world.frames(3)
	assert_int(_life.view()).is_equal(LifeView.View.DOWNED)
	var ceiling_eye := player.global_position.y + _rules.crouch_eye_height_m
	assert_float(_life.downed_camera().pivot().y).is_less_equal(ceiling_eye + EPSILON)
	assert_vector(_life.hider().pivot).is_equal_approx(
		_life.downed_camera().pivot(), Vector3.ONE * EPSILON
	)
	assert_bool(_life.hider().is_active()).is_true()


func test_killed_crouched_under_the_slab_the_pivot_stays_at_the_crouched_eye() -> void:
	await _crouched_player(UNDER)
	_harness.send(DiedEvent.new(_model.own_peer, UNDER))
	_harness.pump()
	await _world.frames(3)
	assert_int(_life.view()).is_equal(LifeView.View.SPECTATE_ABOVE)
	var ceiling_eye := UNDER.y + _rules.crouch_eye_height_m
	assert_float(_life.downed_camera().pivot().y).is_less_equal(ceiling_eye + EPSILON)
	assert_vector(_life.hider().pivot).is_equal_approx(
		_life.downed_camera().pivot(), Vector3.ONE * EPSILON
	)


func test_downed_in_the_open_the_pivot_is_the_standing_eye() -> void:
	var player := await _crouched_player(OPEN)
	_harness.send(KnockedDownEvent.new(_model.own_peer, OPEN))
	_harness.pump()
	player.life = ClientModel.Life.DOWNED
	await _world.frames(3)
	var standing_eye := player.global_position.y + _rules.eye_height_m
	assert_float(_life.downed_camera().pivot().y).is_equal_approx(standing_eye, EPSILON)
	assert_vector(_life.hider().pivot).is_equal_approx(
		_life.downed_camera().pivot(), Vector3.ONE * EPSILON
	)


## The own player crouched at `at` (the crouch key held), followed by the
## LifeView.
func _crouched_player(at: Vector3) -> PlayerController:
	var player := _world.add_player(OPEN)
	player.crouch_held = true
	player.teleport(Transform3D(Basis.IDENTITY, at))
	_life.player = player
	await _world.frames(2)
	assert_bool(player.is_crouched()).is_true()
	return player
