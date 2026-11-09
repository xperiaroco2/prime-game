extends GdUnitTestSuite
## The dead's hall on the network (#1489): a dead joiner, moved to the hall by the host's
## Correction, walks there and its MoveClaims reach the host, which takes them, while it stays dead.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
const RESPAWN_S := 60.0

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	_pair.with_life(RESPAWN_S)
	_pair.with_hall()
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_a_dead_client_walks_the_hall_and_the_host_takes_its_claims() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var client := _pair.client
	var player := client.player()
	var model := client.client().model
	_pair.knock_down(client)
	assert_bool(await _until(func() -> bool: return player.is_downed())).is_true()
	client.life().give_up()
	assert_bool(await _until(func() -> bool: return model.waits_in_hall())).is_true()
	var there := func() -> bool: return player.global_position.distance_to(NetPair.HALL_AT) < 1.5
	assert_bool(await _until(there, 300)).is_true()
	assert_bool(_pair.host_player(client).in_hall).is_true()
	var target := NetPair.HALL_AT + Vector3(3, 0, 0)
	assert_bool(await _pair.walk_to(player, target)).is_true()
	var host_saw := func() -> bool:
		return _pair.host_player(client).position.distance_to(target) < 1.5
	assert_bool(await _until(host_saw, 120)).is_true()
	assert_int(model.life_of(_pair.peer_of(client))).is_equal(ClientModel.Life.DEAD)
	assert_bool(_pair.host_player(client).in_hall).is_true()
	await _pair.stop()


func _until(done: Callable, frames := 120) -> bool:
	for i: int in frames:
		if done.call():
			return true
		await _pair.frames(1)
	return done.call()
