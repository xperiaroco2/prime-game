extends GdUnitTestSuite
## ClientSession on LoadMatch (ARCHITECTURE §4.5 "Loading a level and LoadAck"): a threaded load
## of a map that its own mode lists, map_loaded, then LoadAck with the match id; a bot acks without
## loading; a map its mode does not list, or a load that fails, ends the session.

const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
## Frames a threaded load of the tiny map may take here (it takes one or two).
const MAX_FRAMES := 600

var _harness: Harness


func after_test() -> void:
	_harness.close()


func test_it_acks_after_a_threaded_load_of_a_listed_map() -> void:
	_harness = Harness.new()
	_harness.welcome(&"countdown")
	var loaded: Array[String] = []
	var acks_when_loaded: Array[int] = []
	_harness.session.map_loaded.connect(
		func(path: String, scene: PackedScene) -> void:
			loaded.append(path)
			acks_when_loaded.append(_harness.sent_named(Intents.LOAD_ACK).size())
			var root := scene.instantiate()
			assert_str(String(root.name)).is_equal("TinyMap")
			root.free()
	)
	_harness.send(_load_match(3, Harness.TINY_MAP))
	for i in MAX_FRAMES:
		_harness.pump()
		if not _harness.sent_named(Intents.LOAD_ACK).is_empty():
			break
		await get_tree().process_frame
	var acks := _harness.sent_named(Intents.LOAD_ACK)
	assert_int(acks.size()).is_equal(1)
	assert_int(acks[0].fields["match_id"] as int).is_equal(3)
	assert_int(acks[0].seq).is_equal(1)
	assert_array(loaded).contains_exactly([Harness.TINY_MAP])
	# The owner had the scene before the ack went out.
	assert_array(acks_when_loaded).contains_exactly([0])
	assert_array(_harness.endings).is_empty()


func test_a_bot_acks_without_loading() -> void:
	_harness = Harness.new(false)
	_harness.welcome(&"countdown")
	var loaded: Array[String] = []
	_harness.session.map_loaded.connect(
		func(path: String, _scene: PackedScene) -> void: loaded.append(path)
	)
	_harness.send(_load_match(0, Harness.MISSING_MAP))
	_harness.pump()
	var acks := _harness.sent_named(Intents.LOAD_ACK)
	assert_int(acks.size()).is_equal(1)
	assert_int(acks[0].fields["match_id"] as int).is_equal(0)
	assert_array(loaded).is_empty()


func test_a_map_its_own_mode_does_not_list_ends_the_session() -> void:
	for load_levels: bool in [true, false]:
		_harness = Harness.new(load_levels)
		_harness.welcome(&"countdown")
		_harness.send(_load_match(1, "res://levels/elsewhere/not_in_the_mode.tscn"))
		_harness.pump()
		assert_array(_harness.endings).contains_exactly([ClientSession.UNKNOWN_MAP])
		assert_array(_harness.sent_named(Intents.LOAD_ACK)).is_empty()
		_harness.close()


func test_a_failed_load_ends_the_session() -> void:
	_harness = Harness.new()
	_harness.welcome(&"countdown")
	_harness.send(_load_match(1, Harness.MISSING_MAP))
	for i in MAX_FRAMES:
		_harness.pump()
		if not _harness.endings.is_empty():
			break
		await get_tree().process_frame
	assert_array(_harness.endings).contains_exactly([ClientSession.LOAD_FAILED])
	assert_array(_harness.sent_named(Intents.LOAD_ACK)).is_empty()


func _load_match(match_id: int, map: String) -> LoadMatchEvent:
	var settings: Dictionary[StringName, int] = {&"knives": 2, &"circles": 1}
	return LoadMatchEvent.new(match_id, map, settings)
