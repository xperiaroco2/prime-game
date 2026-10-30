extends GdUnitTestSuite
## A drunk joiner on the network (#1391; ARCHITECTURE §4.7.6 "Drunk", §7.1.20): the host makes it
## 89 drunk (the highest value below the bar's "too much"), its SelfStatus reaches the joiner's
## model and the controller's walk drifts off the keys' line, walking and sprinting, with no
## Correction on either Game: the host's MovementRule accepts the drift with no allowance. The host
## draws the joiner where it walked, from the snapshots, so every peer sees the drift. Sober, the
## same walk keeps the line. A knockdown ends the sway and the drift at once.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
const DRUNK := 89
## The joiner's lobby spot's line: it walks along -X on z = LINE_Z.
const LINE_Z := -2.0

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	_pair.with_bar()
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_a_drunk_joiner_drifts_with_no_correction_and_the_host_sees_it_there() -> void:
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	var model := _pair.client.client().model
	# A quarter turn to the left: along -X, away from the host's spot.
	player.look(PI / 2.0, 0.0)
	player.move_input = Vector2(0.0, 1.0)
	await _pair.frames(60)
	assert_float(player.global_position.x).is_less(-3.0)
	assert_float(player.global_position.z).is_equal_approx(LINE_Z, 0.01)
	player.move_input = Vector2.ZERO
	_pair.make_drunk(_pair.client, DRUNK)
	await _pair.frames(60)
	assert_int(model.drunk).is_equal(DRUNK)
	assert_float(player.drunk_strength()).is_greater(0.9)
	var widest := 0.0
	player.move_input = Vector2(0.0, 1.0)
	for i: int in 150:
		if i == 90:
			player.sprint_held = true
		await _pair.frames(1)
		widest = maxf(widest, absf(player.global_position.z - LINE_Z))
	assert_bool(player.is_sprinting()).is_true()
	player.sprint_held = false
	player.move_input = Vector2.ZERO
	await _pair.frames(30)
	assert_float(widest).is_greater(0.1)
	assert_int(_pair.client.client().corrections).is_equal(0)
	assert_int(_pair.host.client().corrections).is_equal(0)
	var seen := _pair.host.avatars().body_of(_pair.peer_of(_pair.client))
	assert_object(seen).is_not_null()
	assert_vector(seen.global_position).is_equal_approx(player.global_position, Vector3.ONE * 0.05)
	# A knockdown sobers it on the host (#1390) and ends the feel at once on the joiner.
	_pair.knock_down(_pair.client)
	await _pair.frames(10)
	assert_bool(player.is_downed()).is_true()
	assert_float(player.drunk_strength()).is_equal(0.0)
	assert_int(model.drunk).is_equal(0)
	await _pair.stop()
