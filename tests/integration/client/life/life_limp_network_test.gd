extends GdUnitTestSuite
## The limp on the network (ARCHITECTURE §7.1.21, #1393): a host Game and a joined Game over a
## LoopbackHub (NetPair) in the lobby. A joiner the host lays limp (NetPair.limp, as the base
## mode's drunk_too_much reaction would) stays living as the events tell it, but its controller
## holds still as a downed one does, its camera is the downed camera over its own ragdoll, and
## both screens draw it as its ragdoll; once it gets up (the get-up's Correction, the own avatar
## gone from the snapshots) it walks again in first person and the ragdolls go.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_a_limp_client_holds_still_as_its_ragdoll_and_walks_again_when_it_gets_up() -> void:
	assert_bool(await _pair.start()).is_true()
	var joiner := _pair.peer_of(_pair.client)
	var player := _pair.client.player()
	var model := _pair.client.client().model
	var life := _pair.client.life()
	_pair.limp(_pair.client)
	assert_bool(await _until(func() -> bool: return player.is_downed())).is_true()
	assert_int(model.life_of(joiner)).is_equal(ClientModel.Life.ALIVE)
	await _pair.frames(5)
	assert_int(life.view()).is_equal(LifeView.View.DOWNED)
	assert_object(_pair.client.avatars().ragdoll_of(joiner)).is_not_null()
	assert_object(_pair.client.avatars().body_of(joiner)).is_null()
	var drawn := func() -> bool: return _pair.host.avatars().ragdoll_of(joiner) != null
	assert_bool(await _until(drawn)).is_true()
	_pair.limp(_pair.client, true)
	assert_bool(await _until(func() -> bool: return player.is_living())).is_true()
	await _pair.frames(5)
	assert_int(life.view()).is_equal(LifeView.View.FIRST_PERSON)
	assert_object(_pair.client.avatars().ragdoll_of(joiner)).is_null()
	var gone := func() -> bool: return _pair.host.avatars().ragdoll_of(joiner) == null
	assert_bool(await _until(gone)).is_true()
	# Both leave: the dropped ragdolls and the lobby go before the pair is freed.
	await _pair.stop()


func _until(done: Callable, frames := 30) -> bool:
	for i: int in frames:
		if done.call():
			return true
		await _pair.frames(1)
	return done.call()
