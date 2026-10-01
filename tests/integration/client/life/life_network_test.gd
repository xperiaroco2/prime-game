extends GdUnitTestSuite
## The life states on the network (ARCHITECTURE §4.7, M4-9): a host Game and a joined Game over a
## LoopbackHub (NetPair, with the base mode's life rules: the raise, the give-up and a 2 s respawn
## on the fixture's markers). The real controllers, cameras and life views, driven through their
## wish fields and the life view's actions (headless runs have no input):
## - a downed joiner raised by the host's player holds still while it tries to crawl and is never
##   corrected; it stands up living, in first person, invulnerable for the mode's time;
## - a joiner who gives up dies: its controller stays off the living (no layer, no step) however
##   it is driven, it spectates the host's player from its eyes with the lift music, switches to
##   the camera above the host's body when the host goes down, and respawns at a marker in first
##   person, invulnerable on the host's screen, its body gone; never a Correction.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## The fixture's respawn markers (steps_room.tscn).
const RESPAWNS: Array[Vector3] = [Vector3(8, 0, 12), Vector3(12, 0, 12)]
const RESPAWN_S := 2.0

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	_pair.with_life(RESPAWN_S)
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_a_raised_downed_client_holds_still_and_is_never_corrected() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var joiner := _pair.peer_of(_pair.client)
	var downed := _pair.client.player()
	var session := _pair.client.client()
	_pair.knock_down(_pair.client)
	assert_bool(await _until(func() -> bool: return downed.is_downed())).is_true()
	await _pair.frames(10)
	# The own downed player: the downed camera over the body, SightHider casting from its eye.
	var life := _pair.client.life()
	assert_int(life.view()).is_equal(LifeView.View.DOWNED)
	assert_bool(life.downed_camera().camera().current).is_true()
	assert_bool(life.hider().is_active()).is_true()
	var eye_y := downed.global_position.y + FixtureModes.player_rules().eye_height_m
	assert_float(life.downed_camera().camera().global_position.y).is_less_equal(eye_y + 0.001)
	# The host's player walks up to the body and looks at it: E raises it.
	var raiser := _pair.host.player()
	assert_bool(await _face_from(raiser, downed.global_position, 1.3)).is_true()
	assert_int(_pair.host.life().raise_target()).is_equal(joiner)
	var lay := downed.global_position
	_pair.host.life().press_raise()
	assert_bool(await _until(func() -> bool: return downed.held)).is_true()
	assert_int(_pair.host.life().countdowns.raising()).is_equal(joiner)
	# Raised, the joiner tries to crawl away with sprint and jumps: it stays where it lay.
	downed.move_input = Vector2(0.0, 1.0)
	downed.sprint_held = true
	var revived := func() -> bool: return session.model.is_alive(joiner)
	for i: int in 240:
		downed.jump_requested = true
		await _pair.frames(1)
		if revived.call():
			break
		assert_vector(downed.global_position).is_equal_approx(lay, Vector3.ONE * 0.001)
	assert_bool(revived.call()).is_true()
	downed.move_input = Vector2.ZERO
	downed.sprint_held = false
	await _pair.frames(5)
	assert_int(session.corrections).is_equal(0)
	assert_int(_pair.host.client().corrections).is_equal(0)
	# Standing up where it lay, in first person, invulnerable for the mode's 3 s.
	assert_bool(downed.is_living()).is_true()
	assert_bool(downed.held).is_false()
	assert_bool(downed.get_camera().current).is_true()
	assert_bool(life.hider().is_active()).is_false()
	var tick := float(_pair.client.avatars().host_tick())
	assert_float(life.countdowns.invulnerable_left_s(tick)).is_between(2.0, 3.0)
	assert_str(life.hud(tick).title).is_equal("Invulnerable")
	_pair.host.life().release_raise()
	await _pair.stop()


func test_the_dead_stay_dead_spectate_and_respawn_in_first_person() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var joiner := _pair.peer_of(_pair.client)
	var host_peer := _pair.peer_of(_pair.host)
	var player := _pair.client.player()
	var session := _pair.client.client()
	var life := _pair.client.life()
	_pair.knock_down(_pair.client)
	assert_bool(await _until(func() -> bool: return player.is_downed())).is_true()
	life.give_up()
	var dead := func() -> bool: return session.model.life_of(joiner) == ClientModel.Life.DEAD
	assert_bool(await _until(dead)).is_true()
	var lay := player.global_position
	# Dead: no body to move, whatever it is told, and not back on the living layer.
	player.move_input = Vector2(0.0, 1.0)
	player.jump_requested = true
	await _pair.frames(20)
	assert_bool(player.is_living() or player.is_downed()).is_false()
	assert_int(player.collision_layer).is_equal(0)
	assert_vector(player.global_position).is_equal(lay)
	player.move_input = Vector2.ZERO
	# A body where it died, on both screens.
	assert_object(_pair.client.bodies().view_of(joiner)).is_not_null()
	assert_object(_pair.host.bodies().view_of(joiner)).is_not_null()
	# Spectating: the only living player, from its eyes; its own capsule hidden; the lift music.
	assert_int(life.target()).is_equal(host_peer)
	assert_int(life.view()).is_equal(LifeView.View.SPECTATE_EYES)
	assert_bool(life.spectate_camera().current).is_true()
	assert_bool(life.music().playing).is_true()
	var watched := _pair.client.avatars().body_of(host_peer)
	assert_bool((watched.get_node("Mesh") as MeshInstance3D).visible).is_false()
	var eye := watched.global_position + Vector3.UP * FixtureModes.player_rules().eye_height_m
	var camera_at := life.spectate_camera().global_position
	assert_vector(camera_at).is_equal_approx(eye, Vector3.ONE * 0.01)
	var shown := life.hud(float(_pair.client.avatars().host_tick()))
	assert_str(shown.title).is_equal("Dead")
	assert_str("\n".join(shown.lines)).contains("Watching Player1")
	# The target goes down: a new first target, the downed host, watched from above its body.
	_pair.knock_down(_pair.host)
	var above := func() -> bool: return life.view() == LifeView.View.SPECTATE_ABOVE
	assert_bool(await _until(above)).is_true()
	assert_int(life.target()).is_equal(host_peer)
	assert_bool(life.downed_camera().camera().current).is_true()
	assert_bool((watched.get_node("Mesh") as MeshInstance3D).visible).is_true()
	# The respawn: living at a marker, first person, the music off, the body gone, invulnerable
	# on the host's screen; the respawn's Correction a placement, never a correction.
	var living := func() -> bool: return session.model.is_alive(joiner)
	assert_bool(await _until(living, 240)).is_true()
	await _pair.frames(10)
	assert_bool(player.is_living()).is_true()
	var at := player.global_position
	var near := RESPAWNS.any(func(marker: Vector3) -> bool: return marker.distance_to(at) < 0.1)
	assert_bool(near).override_failure_message("respawned at %s" % at).is_true()
	assert_bool(player.get_camera().current).is_true()
	assert_bool(life.music().playing).is_false()
	assert_object(_pair.client.bodies().view_of(joiner)).is_null()
	var seen := _pair.host.avatars().body_of(joiner)
	assert_bool(seen.is_invulnerable()).is_true()
	assert_int(session.corrections).is_equal(0)
	assert_int(session.placements).is_equal(3)
	await _pair.stop()


func test_a_dead_player_who_leaves_hears_no_lift_music_in_the_menu() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var joiner := _pair.peer_of(_pair.client)
	var session := _pair.client.client()
	var life := _pair.client.life()
	_pair.knock_down(_pair.client)
	assert_bool(await _until(func() -> bool: return _pair.client.player().is_downed())).is_true()
	life.give_up()
	assert_bool(await _until(func() -> bool: return life.music().playing)).is_true()
	assert_int(session.model.life_of(joiner)).is_equal(ClientModel.Life.DEAD)
	_pair.client.leave()
	await _pair.frames(10)
	assert_bool(life.music().playing).is_false()
	assert_int(life.view()).is_equal(LifeView.View.FIRST_PERSON)
	await _pair.stop()


## Waits until `done` holds, at most `frames` physics frames; whether it held.
func _until(done: Callable, frames := 30) -> bool:
	for i: int in frames:
		if done.call():
			return true
		await _pair.frames(1)
	return done.call()


## Walks `player` until it stands `distance` from `target` (on the floor), then turns it to look
## at the target, down at a lying body's middle; false when it never got there.
func _face_from(player: PlayerController, target: Vector3, distance: float) -> bool:
	for i: int in 600:
		var to := target - player.global_position
		to.y = 0.0
		player.look(angle_difference(player.rotation.y, atan2(-to.x, -to.z)), 0.0)
		if to.length() <= distance:
			player.move_input = Vector2.ZERO
			await _pair.frames(5)
			# Down at the lying body's middle, as a player does: its capsule lies with its mesh.
			var eye := player.get_camera().global_position
			var aim := target + Vector3.UP * FixtureModes.player_rules().capsule_radius_m
			var flat := Vector2(aim.x - eye.x, aim.z - eye.z).length()
			var want := atan2(aim.y - eye.y, flat)
			player.look(0.0, want - asin(clampf(player.look_vector().y, -1.0, 1.0)))
			await _pair.frames(2)
			return true
		player.move_input = Vector2(0.0, 1.0)
		await _pair.frames(1)
	player.move_input = Vector2.ZERO
	return false
