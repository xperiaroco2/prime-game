extends GdUnitTestSuite
## A placement turns the own player to its marker's facing over the network (#1522): a host Game
## and a joined Game over a LoopbackHub (NetPair) on `steps_room_faced.tscn`, whose lobby markers
## face +z and whose round markers face -x. A joiner's Welcome and the host's own one stand each
## player in the lobby facing +z; the round's start (PlayersPlaced and each player's Correction)
## turns each to -x with a level head, whatever it looked at in the lobby, and the next MoveClaim
## carries that facing; neither placement is a correction. Between placements the player's own look
## stands: a test turns it and nothing turns it back.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
const EPS := 0.0001

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	_pair.with_faced_room()
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_each_player_stands_in_the_lobby_facing_its_marker() -> void:
	assert_bool(await _pair.start()).is_true()
	for game: Game in [_pair.host, _pair.client]:
		var player := game.player()
		var who := "peer %d" % _pair.peer_of(game)
		(
			assert_float(angle_difference(player.rotation.y, PI))
			. override_failure_message(who)
			. is_equal_approx(0.0, EPS)
		)
		assert_float(_pitch(player)).override_failure_message(who).is_equal_approx(0.0, EPS)
		assert_vector(player.look_vector()).is_equal_approx(Vector3.BACK, Vector3.ONE * EPS)
		# What the next MoveClaim says.
		assert_vector(_claim_facing(game)).is_equal_approx(Vector3.BACK, Vector3.ONE * EPS)
	# The own look stands between placements: no later step turns it back.
	var player := _pair.client.player()
	player.look(0.8, 0.5)
	var yaw := player.rotation.y
	await _pair.frames(30)
	assert_float(angle_difference(player.rotation.y, yaw)).is_equal_approx(0.0, EPS)
	assert_float(_pitch(player)).is_equal_approx(0.5, EPS)
	assert_int(_pair.client.client().corrections).is_equal(0)
	await _pair.stop()


func test_the_round_s_start_turns_each_player_to_its_round_marker() -> void:
	assert_bool(await _pair.start()).is_true()
	# Both look up and aside in the lobby, away from the round markers' -x.
	_pair.host.player().look(0.9, 0.7)
	_pair.client.player().look(-0.6, -0.4)
	await _pair.frames(2)
	for game: Game in [_pair.host, _pair.client]:
		assert_float(absf(angle_difference(game.player().rotation.y, PI / 2.0))).is_greater(0.5)
	assert_bool(await _pair.to_round()).is_true()
	for game: Game in [_pair.host, _pair.client]:
		var player := game.player()
		var who := "peer %d" % _pair.peer_of(game)
		(
			assert_float(angle_difference(player.rotation.y, PI / 2.0))
			. override_failure_message(who)
			. is_equal_approx(0.0, EPS)
		)
		assert_float(_pitch(player)).override_failure_message(who).is_equal_approx(0.0, EPS)
		assert_vector(player.look_vector()).is_equal_approx(Vector3.LEFT, Vector3.ONE * EPS)
		assert_vector(_claim_facing(game)).is_equal_approx(Vector3.LEFT, Vector3.ONE * EPS)
		assert_int(game.client().corrections).override_failure_message(who).is_equal(0)
	await _pair.stop()


func _pitch(player: PlayerController) -> float:
	return player.get_camera().get_parent_node_3d().rotation.x


## The facing the session's next MoveClaim carries.
func _claim_facing(game: Game) -> Vector3:
	return game.client().get("_facing") as Vector3
