extends GdUnitTestSuite
## The life states on the network (ARCHITECTURE §4.7, M4-9): a host Game and a joined Game over a
## LoopbackHub (NetPair, with the base mode's life rules: the raise, the give-up and a 2 s respawn
## on the fixture's markers). The real controllers, cameras and life views, driven through their
## wish fields and the life view's actions (headless runs have no input):
## - a downed joiner raised by the host's player holds still while it tries to crawl and is never
##   corrected; it stands up living, in first person, invulnerable for the mode's time, with the
##   look it had (the knockdown's Correction and the revive keep it, #191);
## - a downed joiner gives up on F held (G no longer), through real key events, and F in the round
##   readies nobody (#211);
## - a joiner who gives up dies: its controller stays off the living (no layer, no step) however
##   it is driven, it spectates the host's player from its eyes with the lift music, switches to
##   the camera above the host's body when the host goes down, and respawns at a marker in first
##   person, invulnerable on the host's screen, its body gone; never a Correction;
## - a respawned joiner looks level with the yaw it had while downed, whatever it did downed or
##   dead (mouse motion while dead turns nothing), from the first claim after the respawn (#191);
##   the host's living player, who sees that respawn too, keeps its own look;
## - a joiner who died looking up, never respawned before the round ended, is placed level with
##   the yaw it had by End -> Lobby's PlayersPlaced, and again by the next match's deal after
##   looking up in the lobby, from the placement's Correction on (#240).

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
	# Input's action states are global: nothing stays held for the next suite.
	for action: StringName in [&"give_up", &"ready"]:
		Input.action_release(action)


func test_a_raised_downed_client_holds_still_and_is_never_corrected() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var joiner := _pair.peer_of(_pair.client)
	var downed := _pair.client.player()
	var session := _pair.client.client()
	# The joiner looks a little up and aside: the knockdown's Correction keeps that look (#191:
	# only the own respawn levels it).
	downed.look(0.4, 0.3)
	await _pair.frames(2)
	var yaw := downed.rotation.y
	_pair.knock_down(_pair.client)
	assert_bool(await _until(func() -> bool: return downed.is_downed())).is_true()
	await _pair.frames(10)
	assert_int(session.placements).is_equal(2)
	assert_float(_pitch(downed)).is_equal_approx(0.3, 0.0001)
	assert_float(angle_difference(downed.rotation.y, yaw)).is_equal_approx(0.0, 0.0001)
	# Downed, it looks further up: a revive keeps that look.
	downed.look(0.0, 0.4)
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
	assert_float(_pitch(downed)).is_equal_approx(0.7, 0.0001)
	assert_float(angle_difference(downed.rotation.y, yaw)).is_equal_approx(0.0, 0.0001)
	assert_bool(life.hider().is_active()).is_false()
	var tick := float(_pair.client.avatars().host_tick())
	assert_float(life.countdowns.invulnerable_left_s(tick)).is_between(2.0, 3.0)
	# No own invulnerability read-out (the engineer's answer 2 on PR #167).
	assert_str(life.hud(tick).title).is_empty()
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
	# The HUD names the target, and shows none of the spectator's own numbers (#168). Game._process
	# writes the HUD: the second process_frame comes after a _process that saw the death (#222).
	await get_tree().process_frame
	await get_tree().process_frame
	var hud := _pair.client.ui.hud
	assert_str(hud.spectating_label.text).is_equal("Spectating Player1")
	assert_bool(hud.spectating_label.visible).is_true()
	assert_bool(hud.health_label.visible or hud.stamina_label.visible).is_false()
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


func test_a_respawned_player_looks_level_with_the_yaw_it_had() -> void:
	# #191: after a respawn the player looked up. The engineer's answer on #191: level (head pitch
	# 0), straight ahead, keeping the yaw, as at the round's start; no protocol change.
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var joiner := _pair.peer_of(_pair.client)
	var player := _pair.client.player()
	var session := _pair.client.client()
	_pair.knock_down(_pair.client)
	assert_bool(await _until(func() -> bool: return player.is_downed())).is_true()
	# Downed, the player turns and looks up: the downed camera follows that look.
	player.look(0.6, 1.0)
	await _pair.frames(5)
	var yaw := player.rotation.y
	assert_float(_pitch(player)).is_equal_approx(1.0, 0.001)
	# The host's living player looks up and aside: another player's respawn keeps that look.
	var watcher := _pair.host.player()
	watcher.look(0.3, 0.6)
	var watcher_yaw := watcher.rotation.y
	_pair.client.life().give_up()
	var dead := func() -> bool: return session.model.life_of(joiner) == ClientModel.Life.DEAD
	assert_bool(await _until(dead)).is_true()
	await _pair.frames(2)
	# Dead, the mouse moves right and up: the hidden body neither turns nor tilts its head.
	player.look(0.9, 0.5)
	assert_float(angle_difference(player.rotation.y, yaw)).is_equal_approx(0.0, 0.0001)
	assert_float(_pitch(player)).is_equal_approx(1.0, 0.001)
	# What the next MoveClaim would say at the respawn's Correction (the first claim may go out in
	# that same session step, before the controller's next physics step), and the first claim. The
	# lambdas read the session through the pair: one holding the session would hold itself.
	var respawned: Array[bool] = [false]
	var at_placement: Array[Vector3] = []
	var first_claim: Array[Vector3] = []
	session.event_received.connect(
		func(event_name: StringName, fields: Dictionary) -> void:
			if event_name == &"Respawned" and (fields["peer"] as int) == joiner:
				respawned[0] = true
	)
	session.corrected.connect(
		func(_position: Vector3, _velocity: Vector3) -> void:
			if respawned[0] and at_placement.is_empty():
				at_placement.append(_pair.client.client().get("_facing") as Vector3)
	)
	session.claim_sent.connect(
		func(_epoch: int, _tick: int, _covered: int, _sprint: bool, _moved: bool) -> void:
			if respawned[0] and first_claim.is_empty():
				first_claim.append(_pair.client.client().get("_facing") as Vector3)
	)
	var living := func() -> bool: return session.model.is_alive(joiner)
	assert_bool(await _until(living, 240)).is_true()
	assert_bool(await _until(func() -> bool: return not first_claim.is_empty())).is_true()
	# Level, straight ahead, with the yaw it had while downed.
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
	assert_float(_pitch(player)).is_equal_approx(0.0, 0.0001)
	assert_float(angle_difference(player.rotation.y, yaw)).is_equal_approx(0.0, 0.0001)
	assert_vector(player.look_vector()).is_equal_approx(ahead, Vector3.ONE * 0.0001)
	assert_vector(player.get_camera().global_basis.z * -1.0).is_equal_approx(
		ahead, Vector3.ONE * 0.0001
	)
	assert_int(at_placement.size()).is_equal(1)
	assert_vector(at_placement[0]).is_equal_approx(ahead, Vector3.ONE * 0.0001)
	assert_vector(first_claim[0]).is_equal_approx(ahead, Vector3.ONE * 0.0001)
	# The host's screen draws the respawned joiner with a level head.
	await _pair.frames(30)
	var seen := _pair.host.avatars().body_of(joiner)
	assert_object(seen).is_not_null()
	assert_float(seen.head().rotation.x).is_equal_approx(0.0, 0.001)
	# The host's own client saw the joiner's Respawned too: its living player keeps its look.
	assert_float(_pitch(watcher)).is_equal_approx(0.6, 0.0001)
	assert_float(angle_difference(watcher.rotation.y, watcher_yaw)).is_equal_approx(0.0, 0.0001)
	assert_float(watcher.look_vector().y).is_greater(0.5)
	assert_int(session.corrections).is_equal(0)
	await _pair.stop()


func test_a_player_who_died_looking_up_is_placed_level_by_a_new_match() -> void:
	# #240: a player who died looking up and was next placed by a new match (the own
	# PlayersPlaced), not by a respawn, kept that pitch. The engineer's answer on #240 (option b):
	# every placement into a round starts level with the yaw kept, as the own Respawned has it.
	# No respawn within the test: the round ends first.
	_pair.mode.player_rules.respawn_s = 300.0
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var joiner := _pair.peer_of(_pair.client)
	var player := _pair.client.player()
	var session := _pair.client.client()
	_pair.knock_down(_pair.client)
	assert_bool(await _until(func() -> bool: return player.is_downed())).is_true()
	player.look(0.6, 1.0)
	await _pair.frames(5)
	var yaw := player.rotation.y
	_pair.client.life().give_up()
	var dead := func() -> bool: return session.model.life_of(joiner) == ClientModel.Life.DEAD
	assert_bool(await _until(dead)).is_true()
	assert_float(_pitch(player)).is_equal_approx(1.0, 0.001)
	# What the next MoveClaim would say at the own placement's Correction (the lambdas read the
	# session through the pair: one holding the session would hold itself).
	var placed: Array[bool] = [false]
	var at_placement: Array[Vector3] = []
	session.event_received.connect(
		func(event_name: StringName, fields: Dictionary) -> void:
			if event_name == &"PlayersPlaced" and (fields["spots"] as Dictionary).has(joiner):
				placed[0] = true
	)
	session.corrected.connect(
		func(_position: Vector3, _velocity: Vector3) -> void:
			if placed[0] and at_placement.is_empty():
				at_placement.append(_pair.client.client().get("_facing") as Vector3)
	)
	# The round ends while the joiner is dead; the host's ReturnToLobby places everyone.
	_pair.win()
	var ended := func() -> bool: return session.model.phase == &"end"
	assert_bool(await _until(ended)).is_true()
	assert_float(_pitch(player)).is_equal_approx(1.0, 0.001)
	_pair.host.return_to_lobby()
	var lobby := func() -> bool:
		return session.model.phase == &"lobby" and not at_placement.is_empty()
	assert_bool(await _until(lobby)).is_true()
	await _pair.frames(5)
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
	assert_float(_pitch(player)).is_equal_approx(0.0, 0.0001)
	assert_float(angle_difference(player.rotation.y, yaw)).is_equal_approx(0.0, 0.0001)
	assert_vector(player.look_vector()).is_equal_approx(ahead, Vector3.ONE * 0.0001)
	assert_vector(at_placement[0]).is_equal_approx(ahead, Vector3.ONE * 0.0001)
	# In the lobby the living player looks up and aside; the new match's deal places it level
	# again, with the yaw it had.
	player.look(-0.4, 0.8)
	await _pair.frames(2)
	assert_float(_pitch(player)).is_equal_approx(0.8, 0.0001)
	yaw = player.rotation.y
	placed[0] = false
	at_placement.clear()
	assert_bool(await _pair.to_round()).is_true()
	assert_int(at_placement.size()).is_equal(1)
	ahead = Vector3(-sin(yaw), 0.0, -cos(yaw))
	assert_float(_pitch(player)).is_equal_approx(0.0, 0.0001)
	assert_float(angle_difference(player.rotation.y, yaw)).is_equal_approx(0.0, 0.0001)
	assert_vector(at_placement[0]).is_equal_approx(ahead, Vector3.ONE * 0.0001)
	assert_int(session.corrections).is_equal(0)
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


func test_the_downed_give_up_on_f_held_and_f_readies_nobody_in_the_round() -> void:
	# #211: give-up moved from G to F, Ready's key in the lobby. Through real key events on the
	# joiner's Game (the host's reads no device): F held while living does nothing; G held while
	# downed no longer gives up; F held while downed gives up; no F ever toggles the ready flag.
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var joiner := _pair.peer_of(_pair.client)
	var session := _pair.client.client()
	var ready_before := _ready_of(session.model, joiner)
	_pair.client.device_input = true
	_hold(KEY_F, true)
	await _pair.frames(90)
	_hold(KEY_F, false)
	assert_int(session.model.life_of(joiner)).is_equal(ClientModel.Life.ALIVE)
	_pair.knock_down(_pair.client)
	assert_bool(await _until(func() -> bool: return _pair.client.player().is_downed())).is_true()
	_hold(KEY_G, true)
	await _pair.frames(90)
	_hold(KEY_G, false)
	assert_int(session.model.life_of(joiner)).is_equal(ClientModel.Life.DOWNED)
	_hold(KEY_F, true)
	var dead := func() -> bool: return session.model.life_of(joiner) == ClientModel.Life.DEAD
	assert_bool(await _until(dead, 180)).is_true()
	_hold(KEY_F, false)
	await _pair.frames(10)
	assert_bool(_ready_of(session.model, joiner)).is_equal(ready_before)
	await _pair.stop()


## `peer`'s ready flag in `model`'s roster.
func _ready_of(model: ClientModel, peer: int) -> bool:
	var member: ClientModel.Member = model.roster.get(peer)
	return member != null and member.ready


func _hold(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## The head's pitch of `player`'s first-person view, in radians (up is positive).
func _pitch(player: PlayerController) -> float:
	return player.get_camera().get_parent_node_3d().rotation.x


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
