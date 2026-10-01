extends GdUnitTestSuite
## DecodedView (ARCHITECTURE §4.6) as a ClientSession fills it over a LoopbackHub: the events in
## order, each equal to core/'s to_dict() with its Variant types; the snapshots by tick, a second
## one of a tick kept apart; the voice frames and their seqs by speaker and tick, and the speakers
## per tick in PeerView's shape.

const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
const WireSamples := preload("res://tests/unit/net/messages/wire_samples.gd")

var _harness: Harness


func before_test() -> void:
	_harness = Harness.new()


func after_test() -> void:
	_harness.close()


func test_it_holds_the_events_in_order_as_core_emitted_them() -> void:
	var sent: Array[MatchEvent] = [
		PlayerJoinedEvent.new(3, "Player3", Vector3(1, 0, 1)),
		ReadyChangedEvent.new(3, true),
		PhaseChangedEvent.new(&"countdown", 400),
		ItemSpawnedEvent.new(4, &"package", Vector3(2, 0, 2), 1, Color.RED),
		ItemSpawnedEvent.new(5, &"knife", Vector3(3, 0, 3)),
		TeammatesEvent.new(&"dissident", PackedInt32Array([2, 3])),
		SelfStatusEvent.new(2, 90000, 50000, true),
	]
	var welcome := _harness.welcome()
	for event: MatchEvent in sent:
		_harness.send(event)
	_harness.pump()
	var view := _harness.session.view
	sent.push_front(welcome)
	assert_int(view.events.size()).is_equal(sent.size())
	for i in sent.size():
		assert_str(String(view.events[i].name)).is_equal(String(sent[i].event_name()))
		var same := WireSamples.same(view.events[i].fields, sent[i].to_dict())
		assert_bool(same).override_failure_message("event %d differs" % i).is_true()
	assert_array(view.events_named(&"ItemSpawned")).has_size(2)
	assert_str(String(view.event_names()[0])).is_equal("Welcome")


func test_it_holds_the_snapshots_by_tick() -> void:
	_harness.welcome()
	_harness.send_message(_snapshot(10, {1: _avatar(Vector3(1, 0, 0))}))
	_harness.pump()
	_harness.send_message(_snapshot(11, {1: _avatar(Vector3(2, 0, 0))}))
	_harness.pump()
	var snapshots := _harness.session.view.snapshots
	assert_array(snapshots.keys()).contains_exactly([10, 11])
	var eleven: Dictionary = snapshots[11]["avatars"]
	var avatar: Dictionary = eleven[1]
	assert_vector(avatar["position"] as Vector3).is_equal(Vector3(2, 0, 0))
	# The model keeps the newest one's avatars.
	var model := _harness.session.model
	assert_int(model.snapshot_tick).is_equal(11)
	assert_bool(WireSamples.same(model.avatars, eleven)).is_true()


func test_a_second_snapshot_of_a_tick_overwrites_nothing() -> void:
	# The host sends one snapshot per tick; a second of the same tick (in another poll, so the LATEST
	# lane delivers both) must stay visible to the leak test, not replace the first.
	_harness.welcome()
	_harness.send_message(_snapshot(10, {1: _avatar(Vector3(1, 0, 0))}))
	_harness.pump()
	_harness.send_message(_snapshot(10, {1: _avatar(Vector3(2, 0, 0)), 3: _avatar(Vector3.ONE)}))
	_harness.pump()
	var view := _harness.session.view
	var first: Dictionary = view.snapshots[10]["avatars"]
	assert_array(first.keys()).contains_exactly([1])
	assert_vector((first[1] as Dictionary)["position"] as Vector3).is_equal(Vector3(1, 0, 0))
	assert_int(view.repeated_snapshots.size()).is_equal(1)
	var second: Dictionary = view.repeated_snapshots[0]["avatars"]
	assert_array(second.keys()).contains_exactly([1, 3])


func test_a_player_leaving_leaves_the_recorded_snapshot_as_decoded() -> void:
	_harness.welcome()
	_harness.send_message(_snapshot(12, {1: _avatar(Vector3.ZERO), 2: _avatar(Vector3.ONE)}))
	_harness.pump()
	_harness.send(PlayerLeftEvent.new(2))
	_harness.pump()
	var recorded: Dictionary = _harness.session.view.snapshots[12]["avatars"]
	assert_array(recorded.keys()).contains_exactly_in_any_order([1, 2])
	assert_array(_harness.session.model.avatars.keys()).contains_exactly([1])


func test_the_model_folds_settings_and_placements_as_decoded() -> void:
	_harness.welcome()
	var numbers: Dictionary[StringName, int] = {&"knives": 4, &"tasks": 2}
	var sets: Dictionary[StringName, PackedStringArray] = {
		&"banned_task_types": PackedStringArray(["delivery"])
	}
	var problems := PackedStringArray(["2 knife marker(s) needed, the map has 0"])
	var map := "res://levels/maps/b.tscn"
	_harness.send(
		SettingsChangedEvent.new(numbers, map, 2, Demands.new(null), null, problems, sets)
	)
	var placed: Dictionary[int, Vector3] = {1: Vector3(4, 0, 4), 2: Vector3(5, 0, 5)}
	_harness.send(PlayersPlacedEvent.new(placed))
	_harness.pump()
	var model := _harness.session.model
	assert_bool(WireSamples.same(model.settings, numbers)).is_true()
	assert_bool(WireSamples.same(model.id_sets, sets)).is_true()
	assert_str(model.map).is_equal(map)
	assert_array(model.shortfalls).is_equal(problems)
	assert_vector(model.spots[1]).is_equal(Vector3(4, 0, 4))
	assert_vector(model.spots[2]).is_equal(Vector3(5, 0, 5))


func test_it_holds_the_voice_by_speaker_and_tick() -> void:
	_harness.welcome()
	var heard: Array[int] = []
	_harness.session.voice_received.connect(
		func(speaker: int, _tick: int, _opus: PackedByteArray) -> void: heard.append(speaker)
	)
	_harness.send_message(_voice(1, 0, 20, PackedByteArray([1])))
	_harness.send_message(_voice(1, 1, 20, PackedByteArray([2, 2])))
	_harness.send_message(_voice(3, 0, 20, PackedByteArray([3])))
	_harness.send_message(_voice(3, 1, 21, PackedByteArray([4])))
	_harness.pump()
	var view := _harness.session.view
	assert_array(view.frames(1, 20)).is_equal([PackedByteArray([1]), PackedByteArray([2, 2])])
	assert_array(view.frames(3, 21)).is_equal([PackedByteArray([4])])
	assert_array(view.frames(3, 22)).is_empty()
	# Each frame's seq, in the same order.
	assert_array(view.voice_seqs[Vector2i(1, 20)]).is_equal(PackedInt32Array([0, 1]))
	assert_array(view.voice_seqs[Vector2i(3, 21)]).is_equal(PackedInt32Array([1]))
	var speakers := view.speakers()
	assert_array(speakers[20]).is_equal(PackedInt32Array([1, 3]))
	assert_array(speakers[21]).is_equal(PackedInt32Array([3]))
	assert_array(heard).contains_exactly([1, 1, 3, 3])


func test_a_payload_that_does_not_decode_is_counted_and_dropped() -> void:
	_harness.welcome()
	var events := _harness.session.view.events.size()
	# A PlayerLeft of peer 0, which the codec rejects (NetFrame passes it: the size is right).
	_harness.host.send(
		_harness.peer, _harness.schema.kind_of(&"PlayerLeft"), PackedByteArray([0, 0, 0, 0])
	)
	_harness.pump()
	assert_int(_harness.session.bad_payloads).is_equal(1)
	assert_int(_harness.session.view.events.size()).is_equal(events)
	assert_array(_harness.endings).is_empty()


static func _snapshot(tick: int, avatars: Dictionary) -> WireMessage:
	return WireMessage.new(&"Snapshot", {"tick": tick, "avatars": avatars})


static func _avatar(at: Vector3) -> Dictionary:
	return {
		"position": at,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"downed": false,
		"invulnerable": false,
		"held_item": -1,
	}


static func _voice(speaker: int, seq: int, tick: int, opus: PackedByteArray) -> WireMessage:
	return WireMessage.new(
		&"VoiceDown", {"speaker": speaker, "seq": seq, "tick": tick, "opus": opus}
	)
