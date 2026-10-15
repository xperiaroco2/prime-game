extends GdUnitTestSuite
## The downed (knocked-down) player in the first-person controller over real physics steps (Jolt,
## headless). It holds still where it lay and only looks (KE4, the knockdown ADR of 2026-10-10):
## no movement, no gravity, no sprint and no jump, and its stamina regenerates as usual. It is on
## the downed layer and lies down (its mesh; the capsule stays standing). A dead player has no body
## and does not look around, and look_level() levels a respawned head (#191), and the own
## placement's (#240). Forward is -Z. Each test builds its own small world.

const SPEED_TOLERANCE := 0.05
const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")

var _rules := FixtureModes.player_rules()
var _world: PlayerTestWorld


func before_test() -> void:
	_world = PlayerTestWorld.new()
	add_child(_world)


func after_test() -> void:
	_world.free()


func test_downed_is_on_the_downed_layer_and_collides_with_the_level_only() -> void:
	# The living collide with the level and the movers (the car repair's car, RE8 (a), #811), never
	# with each other: they push each other instead (the push suite).
	var living := PhysicsLayers.WORLD | PhysicsLayers.MOVERS
	var player := _world.add_player(Vector3.ZERO)
	assert_int(player.collision_layer).is_equal(PhysicsLayers.LIVING)
	assert_int(player.collision_mask).is_equal(living)
	player.life = ClientModel.Life.DOWNED
	assert_int(player.collision_layer).is_equal(PhysicsLayers.DOWNED)
	assert_int(player.collision_mask).is_equal(PhysicsLayers.WORLD)
	player.life = ClientModel.Life.ALIVE
	assert_int(player.collision_layer).is_equal(PhysicsLayers.LIVING)
	assert_int(player.collision_mask).is_equal(living)


func test_downed_holds_still_however_it_is_driven() -> void:
	# KE4 (the knockdown ADR of 2026-10-10): a knocked-down player moves nothing, never sprints and
	# never jumps, whatever it asks; the host takes the look of its claims only.
	var player := _world.add_downed(Vector3.ZERO)
	await _world.frames(10)
	var lay := player.global_position
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	for i: int in 90:
		player.jump_requested = true
		await _world.frames(1)
		assert_vector(player.global_position).is_equal(lay)
		assert_bool(player.is_sprinting()).is_false()
	assert_vector(player.velocity).is_equal(Vector3.ZERO)


func test_downed_stays_where_it_lay_with_no_gravity() -> void:
	# The host keeps a knocked-down body where it lay and takes no place from its claims (KE4), so
	# the client neither falls nor walks away from there.
	var player := _world.add_downed(Vector3(0.0, 2.0, 0.0))
	await _world.frames(45)
	assert_vector(player.global_position).is_equal(Vector3(0.0, 2.0, 0.0))


func test_downed_stamina_spends_nothing_and_regenerates() -> void:
	# The downed are never in the sprint state and spend none: their stamina regenerates as
	# usual (StaminaLedger), with sprint held and jumps asked for.
	var player := _world.add_downed(Vector3.ZERO)
	await _world.frames(10)
	_world.stand_in(player).set_status(Ticks.thousandths(50.0))
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	for i: int in 60:
		player.jump_requested = true
		await _world.frames(1)
	var one_second := 50.0 + _rules.stamina_regen_per_s
	var regenerated := minf(float(_rules.stamina), one_second)
	# A second of 60 Hz steps settles 19 or 20 whole ticks, by where the carry stood.
	var one_tick := _rules.stamina_regen_per_s / float(Ticks.RATE)
	assert_float(player.stamina.get_stamina()).is_between(regenerated - one_tick, regenerated)
	assert_float(player.stamina.get_stamina()).is_greater(50.0)


func test_turning_back_into_the_living_limits_it_by_stamina_again() -> void:
	var player := _world.add_downed(Vector3.ZERO)
	await _world.frames(10)
	_world.stand_in(player).set_status(Ticks.thousandths(0.0))
	player.life = ClientModel.Life.ALIVE
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var speed: float = await _world.measure_speed(player, 5, 10)
	assert_float(speed).is_equal_approx(_rules.walk_speed_mps, SPEED_TOLERANCE)
	assert_bool(player.is_sprinting()).is_false()


func test_the_controller_draws_no_body_while_downed_and_the_dead_have_none() -> void:
	# The knocked-down own body is the own avatar's ragdoll (AvatarViews, KE5 and KE7; its colour is
	# avatar_views_test's), never a mesh of the controller held where the knockdown found it.
	var player := _world.add_player(Vector3.ZERO)
	player.life = ClientModel.Life.DOWNED
	assert_int(player.collision_layer).is_equal(PhysicsLayers.DOWNED)
	assert_array(_shown_meshes(player)).is_empty()
	player.set_rules(player.rules)
	assert_array(_shown_meshes(player)).is_empty()
	player.life = ClientModel.Life.DEAD
	assert_array(_shown_meshes(player)).is_empty()
	assert_int(player.collision_layer).is_equal(0)
	assert_bool(player.is_living() or player.is_downed()).is_false()


func test_the_dead_never_move_however_they_are_driven() -> void:
	var player := _world.add_player(Vector3(0.0, 1.0, 0.0))
	player.life = ClientModel.Life.DEAD
	player.move_input = Vector2(0.0, 1.0)
	player.jump_requested = true
	await _world.frames(30)
	assert_vector(player.global_position).is_equal(Vector3(0.0, 1.0, 0.0))


func test_the_downed_look_around_and_the_dead_neither_turn_nor_tilt_the_head() -> void:
	# #191: the dead have no avatar; mouse motion while spectating tilted the hidden head.
	var player := _world.add_downed(Vector3.ZERO)
	player.look(0.5, 0.3)
	assert_float(player.rotation.y).is_equal_approx(0.5, 0.0001)
	assert_float(_pitch(player)).is_equal_approx(0.3, 0.0001)
	for life: ClientModel.Life in [ClientModel.Life.DEAD, ClientModel.Life.LEFT]:
		player.life = life
		player.look(0.9, 0.8)
		assert_float(player.rotation.y).is_equal_approx(0.5, 0.0001)
		assert_float(_pitch(player)).is_equal_approx(0.3, 0.0001)


func test_look_level_levels_the_head_and_keeps_the_yaw() -> void:
	# A respawn's look (the engineer's answer on #191): level, the yaw kept.
	var player := _world.add_player(Vector3.ZERO)
	player.look(-1.2, -0.7)
	player.look_level()
	assert_float(_pitch(player)).is_equal_approx(0.0, 0.0001)
	assert_float(player.rotation.y).is_equal_approx(-1.2, 0.0001)
	var ahead := Vector3(sin(1.2), 0.0, -cos(1.2))
	assert_vector(player.look_vector()).is_equal_approx(ahead, Vector3.ONE * 0.0001)


func test_only_the_own_respawn_and_placement_level_the_look() -> void:
	# #240 (the engineer's answer, option b): a PlayersPlaced naming the own player levels its look
	# as the own Respawned does (#191); another player's respawn or placement keeps it.
	var player := _world.add_player(Vector3.ZERO)
	var schema := WireSchema.game(OS.is_debug_build())
	var transport := LoopbackTransport.new(schema.kind_table(), LoopbackHub.new())
	var session := ClientSession.new(transport, FixtureBaseMode.mode(), schema)
	session.model.own_peer = 2
	player.attach(session)
	player.look(0.5, 0.4)
	var others: Dictionary[int, Vector3] = {3: Vector3.ONE}
	session.event_received.emit(&"PlayersPlaced", {"spots": others})
	session.event_received.emit(&"Respawned", {"peer": 3})
	assert_float(_pitch(player)).is_equal_approx(0.4, 0.0001)
	var everyone: Dictionary[int, Vector3] = {2: Vector3.ZERO, 3: Vector3.ONE}
	session.event_received.emit(&"PlayersPlaced", {"spots": everyone})
	assert_float(_pitch(player)).is_equal_approx(0.0, 0.0001)
	assert_float(player.rotation.y).is_equal_approx(0.5, 0.0001)


func test_a_revived_player_walks_on_from_where_it_lay() -> void:
	# Revived turns it living (Game's life fold), and it walks again from where it lay.
	var player := _world.add_downed(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(30)
	assert_vector(player.global_position).is_equal(Vector3.ZERO)
	player.life = ClientModel.Life.ALIVE
	await _world.frames(30)
	assert_float(player.global_position.z).is_less(-0.3)


## The head's pitch of `player`'s first-person view, in radians (up is positive).
func _pitch(player: PlayerController) -> float:
	return player.get_camera().get_parent_node_3d().rotation.x


## The meshes under `player` drawn now.
func _shown_meshes(player: PlayerController) -> Array[Node]:
	return player.find_children("*", "MeshInstance3D", true, false).filter(
		func(mesh: Node) -> bool: return (mesh as MeshInstance3D).is_visible_in_tree()
	)
