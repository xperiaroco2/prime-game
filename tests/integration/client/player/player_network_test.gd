extends GdUnitTestSuite
## The real PlayerController on the network (ARCHITECTURE §4.7 and §7, M4-7): a joined Game's
## player walks, sprints, jumps and climbs steps on a fixture level, claiming through its
## ClientSession over a LoopbackHub to the host's HostSession, which checks every claim
## (MovementRule) against its own copy of the level. Honest play is corrected 0 times; a teleport
## the test forces on the controller (a refused claim) is corrected once, keeping the player's look
## (#191), and play goes on without another. The host's own placement at the round's start is one
## placement and no correction, the claims of the old epoch still in flight draw none, and the
## placed joiner snaps on the host's screen. The host sees the joiner where it walked, through the
## snapshots and SnapshotBuffer. A downed joiner crawls from the KnockedDown on (Game's own life
## fold) and its crawl (M4-2's crawl check) is corrected 0 times: on flat floor, on a clock that
## stands still and then jumps (the claims count physics steps, SessionNode), and up the steps.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## The top of the fixture's stairs.
const TOP_Y := 1.2
## The most process frames _until() waits.
const UNTIL_FRAMES := 120

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_walking_sprinting_jumping_and_steps_are_never_corrected() -> void:
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	assert_vector(player.global_position).is_equal_approx(Vector3(0, 0, -2), Vector3.ONE * 0.01)
	# A quarter turn to the right: toward the stairs along +X. Walk, then sprint up the steps.
	player.look(-PI / 2.0, 0.0)
	player.move_input = Vector2(0.0, 1.0)
	await _pair.frames(60)
	assert_float(player.global_position.x).is_between(4.0, 5.0)
	player.sprint_held = true
	await _pair.frames(60)
	assert_bool(player.is_sprinting()).is_true()
	assert_float(player.global_position.y).is_equal_approx(TOP_Y, 0.02)
	assert_float(player.global_position.x).is_greater(10.0)
	# Turn back, jump on the top while looking down a little, then walk down the steps.
	player.sprint_held = false
	player.move_input = Vector2.ZERO
	player.look(PI, -0.4)
	await _pair.frames(10)
	player.jump_requested = true
	await _pair.frames(70)
	assert_float(player.global_position.y).is_equal_approx(TOP_Y, 0.02)
	player.move_input = Vector2(0.0, 1.0)
	await _pair.frames(150)
	assert_float(player.global_position.y).is_equal_approx(0.0, 0.02)
	assert_float(player.global_position.x).is_less(6.0)
	# Strafe and jump on the floor, then stand.
	player.move_input = Vector2(1.0, 0.0)
	player.jump_requested = true
	await _pair.frames(60)
	player.move_input = Vector2.ZERO
	await _pair.frames(30)
	assert_int(_pair.client.client().corrections).is_equal(0)
	assert_int(_pair.host.client().corrections).is_equal(0)
	# The host draws the joiner where it stands, from the snapshots.
	var seen := _pair.host.avatars().body_of(_pair.peer_of(_pair.client))
	assert_object(seen).is_not_null()
	assert_vector(seen.global_position).is_equal_approx(player.global_position, Vector3.ONE * 0.05)
	await _pair.stop()


func test_a_refused_teleport_is_corrected_once_and_play_goes_on() -> void:
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	var session := _pair.client.client()
	# A look up and aside, which the Correction keeps (#191: only the own respawn levels it).
	player.look(0.5, -0.6)
	await _pair.frames(2)
	var yaw := player.rotation.y
	var stood := player.global_position
	# The test puts the controller 5 m away at once: no walk covers that in a tick.
	player.teleport(Transform3D(player.global_basis, stood + Vector3(5.0, 0.0, 0.0)))
	for i: int in 30:
		if session.corrections > 0:
			break
		await _pair.frames(1)
	assert_int(session.corrections).is_equal(1)
	# The Correction put it back where the host last accepted it.
	await _pair.frames(1)
	assert_vector(player.global_position).is_equal_approx(stood, Vector3.ONE * 0.05)
	assert_float(player.get_camera().get_parent_node_3d().rotation.x).is_equal_approx(-0.6, 0.0001)
	assert_float(angle_difference(player.rotation.y, yaw)).is_equal_approx(0.0, 0.0001)
	player.look(-0.5, 0.0)
	# Play goes on under the new epoch: walking and a jump draw no further Correction.
	player.move_input = Vector2(0.0, -1.0)
	player.jump_requested = true
	await _pair.frames(90)
	player.move_input = Vector2.ZERO
	await _pair.frames(20)
	assert_float(player.global_position.z).is_greater(stood.z + 3.0)
	assert_int(session.corrections).is_equal(1)
	assert_int(session.placements).is_equal(0)
	await _pair.stop()


func test_the_round_placement_is_no_correction_and_the_placed_player_snaps() -> void:
	assert_bool(await _pair.start()).is_true()
	var joiner := _pair.peer_of(_pair.client)
	var lobby_spot := _pair.client.player().global_position
	# Every pose the host draws of the joiner on the way: at the lobby spot, or later where it is
	# placed; never anywhere between.
	var seen: Array[Vector3] = []
	var record := func() -> void:
		var body := _pair.host.avatars().body_of(joiner)
		if body != null and body.is_inside_tree():
			seen.append(body.global_position)
	assert_bool(await _pair.to_round(record)).is_true()
	var placed := _pair.client.client().model.spots[joiner]
	assert_vector(_pair.client.player().global_position).is_equal_approx(placed, Vector3.ONE * 0.05)
	for game: Game in [_pair.host, _pair.client]:
		assert_int(game.client().placements).is_equal(1)
		assert_int(game.client().corrections).is_equal(0)
	for i: int in 20:
		await _pair.frames(1)
		record.call()
	for at: Vector3 in seen:
		var near := at.distance_to(lobby_spot) < 0.1 or at.distance_to(placed) < 0.1
		assert_bool(near).override_failure_message("drawn between the spots at %s" % at).is_true()
	assert_vector(seen.back() as Vector3).is_equal_approx(placed, Vector3.ONE * 0.1)
	# Play goes on in the round: walking and a jump draw no Correction.
	var player := _pair.client.player()
	player.move_input = Vector2(0.0, 1.0)
	player.jump_requested = true
	await _pair.frames(60)
	player.move_input = Vector2.ZERO
	await _pair.frames(20)
	assert_float(player.global_position.distance_to(placed)).is_greater(2.0)
	assert_int(_pair.client.client().corrections).is_equal(0)
	assert_int(_pair.client.client().placements).is_equal(1)
	await _pair.stop()


func test_a_downed_crawl_is_never_corrected() -> void:
	await _crawl_on_the_floor()


func test_a_downed_crawl_on_an_uneven_clock_is_never_corrected() -> void:
	# The clock stands still for a frame and then advances two: on the real clock a claim of one
	# client tick would then hold 4 physics steps of crawl, past the host's crawl allowance.
	_pair.uneven = true
	await _crawl_on_the_floor()


func test_a_downed_crawl_up_the_steps_is_never_corrected() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var player := _pair.client.player()
	var session := _pair.client.client()
	var joiner := _pair.peer_of(_pair.client)
	# From the round spot to the foot of the stairs, then face them (+X).
	assert_bool(await _pair.walk_to(player, Vector3(5.0, 0.0, -2.0))).is_true()
	player.move_input = Vector2.ZERO
	player.look(angle_difference(player.rotation.y, -PI / 2.0), 0.0)
	await _pair.frames(10)
	_pair.knock_down(_pair.client)
	assert_bool(await _until_downed(player)).is_true()
	await _pair.frames(5)
	player.move_input = Vector2(0.0, 1.0)
	await _pair.frames(270)
	player.move_input = Vector2.ZERO
	await _pair.frames(20)
	assert_int(session.model.life_of(joiner)).is_equal(ClientModel.Life.DOWNED)
	assert_float(player.global_position.x).is_greater(8.0)
	assert_float(player.global_position.y).is_equal_approx(TOP_Y, 0.02)
	assert_int(session.corrections).is_equal(0)
	assert_int(session.placements).is_equal(2)
	await _pair.stop()


func test_the_debug_overlay_shows_each_side_its_numbers() -> void:
	assert_bool(await _pair.start()).is_true()
	for game: Game in [_pair.host, _pair.client]:
		game.overlay().visible = true
	await _pair.frames(3)
	# Physics steps can all run inside one idle frame, and process_frame is emitted before that
	# frame's _process: the second one comes after a Game._process that saw the overlay visible.
	await get_tree().process_frame
	await get_tree().process_frame
	var joined := _pair.client.overlay().label.text
	assert_str(joined).contains("corrections: 0")
	assert_str(joined).contains("placements: 0")
	assert_str(joined).not_contains("host:")
	var hosting := _pair.host.overlay().label.text
	assert_str(hosting).contains("corrections: 0")
	assert_str(hosting).contains("host:")
	await _pair.stop()


## The host's voice relay counters (the M5 ADR §3 item 11, M5-4): totals in the Lobby on the
## host's overlay only, and none during the Round, where they would tell the host's player how many
## hear them.
func test_the_host_s_relay_counters_show_in_the_lobby_and_never_in_the_round() -> void:
	assert_bool(await _pair.start()).is_true()
	for game: Game in [_pair.host, _pair.client]:
		game.overlay().visible = true
	var hosting := _pair.host.overlay().relay_label
	# Game fills the overlay in its per-frame update: wait for one, bounded (#222's flake).
	await _until(func() -> bool: return not hosting.text.is_empty())
	assert_bool(hosting.visible).is_true()
	assert_str(hosting.text).contains("host voice (session totals):")
	assert_str(hosting.text).contains("voice_sent: ")
	assert_bool(_pair.client.overlay().relay_label.visible).is_false()
	assert_bool(await _pair.to_round()).is_true()
	await _until(func() -> bool: return hosting.text == DebugOverlay.RELAY_HIDDEN)
	assert_str(hosting.text).is_equal(DebugOverlay.RELAY_HIDDEN)
	assert_str(_pair.host.overlay().label.text).not_contains("voice_")
	assert_bool(_pair.client.overlay().relay_label.visible).is_false()
	await _pair.stop()


## Waits process frames until `done` returns true, at most UNTIL_FRAMES.
func _until(done: Callable) -> void:
	for _i in UNTIL_FRAMES:
		if done.call():
			return
		await get_tree().process_frame


## The host knocks the joiner down in the round. Game's life fold makes its controller crawl
## (its life) from the KnockedDown on; it crawls holding sprint and asking to jump all
## along: the host's crawl check (M4-2) never corrects it, and the knockdown's Correction counts
## as a placement.
func _crawl_on_the_floor() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var player := _pair.client.player()
	var session := _pair.client.client()
	var joiner := _pair.peer_of(_pair.client)
	# Walking at the knockdown: the walk's claims still in flight are dropped as stale.
	player.move_input = Vector2(0.0, 1.0)
	await _pair.frames(10)
	_pair.knock_down(_pair.client)
	assert_bool(await _until_downed(player)).is_true()
	await _pair.frames(5)
	var lay := player.global_position
	player.sprint_held = true
	for i: int in 180:
		player.jump_requested = true
		await _pair.frames(1)
	player.move_input = Vector2.ZERO
	player.sprint_held = false
	await _pair.frames(20)
	assert_int(session.model.life_of(joiner)).is_equal(ClientModel.Life.DOWNED)
	assert_float(player.global_position.distance_to(lay)).is_between(2.5, 3.2)
	assert_float(player.global_position.y).is_equal_approx(lay.y, 0.01)
	assert_bool(player.is_sprinting()).is_false()
	assert_int(session.corrections).is_equal(0)
	assert_int(session.placements).is_equal(2)
	# The host draws the downed joiner where it crawled.
	var seen := _pair.host.avatars().body_of(joiner)
	assert_vector(seen.global_position).is_equal_approx(player.global_position, Vector3.ONE * 0.05)
	await _pair.stop()


## Waits until Game made `player` crawl; false after 10 frames.
func _until_downed(player: PlayerController) -> bool:
	for i: int in 10:
		if player.is_downed():
			return true
		await _pair.frames(1)
	return player.is_downed()
