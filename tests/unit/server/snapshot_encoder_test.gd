extends GdUnitTestSuite
## SnapshotEncoder (ARCHITECTURE §4.5 "Snapshots", #1234): each avatar's record encoded once per
## tick, and every viewer's payload byte for byte what WireSchema.encode gives for the Snapshot of
## the avatars Match.snapshot_for gave that viewer, a knocked-down viewer's own avatar included; an
## entry's bytes reused only for an equal record of the same types; the codec's refusals kept.

const Samples := preload("res://tests/unit/net/messages/wire_samples.gd")
const EngineErrors := preload("res://tests/unit/net/messages/engine_errors.gd")

var _schema := WireSchema.game(true)
var _errors: EngineErrors


func before_test() -> void:
	_errors = EngineErrors.new()
	_errors.start()


func after_test() -> void:
	_errors.stop()


func test_it_takes_the_snapshot_rows_kind_cap_and_most_avatars() -> void:
	var encoder := SnapshotEncoder.new(_schema)
	var row := _schema.row_named(&"Snapshot")
	assert_int(encoder.kind).is_equal(row.kind)
	assert_int(encoder.cap).is_equal(row.cap)
	assert_int(encoder.max_avatars).is_equal(WireSchema.MAX_AVATARS)


## The header shortcut patches the last byte of the empty payload: avatars must be the row's last
## field and its count one byte.
func test_avatars_is_the_last_field_of_the_row_and_counted_in_one_byte() -> void:
	var row := _schema.row_named(&"Snapshot")
	assert_str((row.fields.back() as WireField).name).is_equal(SnapshotEncoder.AVATARS)
	assert_bool(row.field_named(SnapshotEncoder.AVATARS).max_count <= 255).is_true()


func test_every_viewers_payload_is_the_codecs_for_its_snapshot_tick_after_tick() -> void:
	var game := _full_round()
	var peers := game.state.present_peers()
	var downed := peers.back() as int
	game.state.player(downed).life = PlayerState.Life.DOWNED
	game.state.player(2).life = PlayerState.Life.DEAD
	var encoder := SnapshotEncoder.new(_schema)
	var compared := 0
	for round_trip in 3:
		FixtureModes.run_ticks(game, 1)
		# Avatars move between ticks: last tick's entries must not stay.
		game.state.player(3).position += Vector3(0.5, 0, 0.25)
		var tick := game.ticked_through()
		encoder.start(tick)
		for viewer: int in peers:
			var avatars: Dictionary = game.snapshot_for(viewer)["avatars"]
			var payload := encoder.payload(avatars)
			assert_bool(payload.is_empty()).is_false()
			assert_bool(payload == _encoded(tick, avatars)).is_true()
			var decoded := _decoded(payload)
			assert_bool(Samples.same(decoded, avatars)).is_true()
			assert_bool(decoded.has(2)).is_false()
			assert_bool(decoded.has(viewer)).is_equal(viewer == downed)
			compared += 1
	assert_int(compared).is_equal(3 * peers.size())
	assert_int(_errors.count()).is_equal(0)


func test_the_wires_worst_case_of_every_avatar_is_the_codecs() -> void:
	var game := _full_round()
	var avatars: Dictionary = game.snapshot_for(1)["avatars"]
	var padded := avatars.duplicate(true)
	for peer in range(1, WireSchema.MAX_AVATARS + 1):
		if not padded.has(peer):
			padded[peer] = (avatars[2] as Dictionary).duplicate()
	assert_int(padded.size()).is_equal(WireSchema.MAX_AVATARS)
	var encoder := SnapshotEncoder.new(_schema)
	encoder.start(0xFFFFFFFE)
	var payload := encoder.payload(padded)
	assert_bool(payload.is_empty()).is_false()
	assert_bool(payload == _encoded(0xFFFFFFFE, padded)).is_true()
	assert_int(_errors.count()).is_equal(0)


func test_an_entry_is_reused_only_for_an_equal_record_of_the_same_types() -> void:
	var encoder := SnapshotEncoder.new(_schema)
	encoder.start(41)
	var moved := _avatar()
	moved["position"] = Vector3(4, 0, 4)
	var holding := _avatar()
	holding["held_item"] = 3
	var first := {2: _avatar(), 5: holding}
	var other := {2: moved, 5: holding}
	for avatars: Dictionary in [first, other, first]:
		var each := encoder.payload(avatars)
		assert_bool(each == _encoded(41, avatars)).is_true()
		assert_bool(Samples.same(_decoded(each), avatars)).is_true()
	assert_int(_errors.count()).is_equal(0)
	# -0.0 == 0.0, but their f32 bytes differ: `==` would hand one viewer the other's bytes.
	var signed := _avatar()
	signed["velocity"] = Vector3(-0.0, 0, 0)
	assert_bool(signed == _avatar()).is_true()
	var with_signed := {2: signed, 5: holding}
	var payload := encoder.payload(with_signed)
	assert_bool(payload == _encoded(41, with_signed)).is_true()
	assert_bool(payload == _encoded(41, first)).is_false()
	assert_bool(encoder.payload(first) == _encoded(41, first)).is_true()
	# The wire's item is an int: a 3.0 is refused as the codec refuses it, never sent as 3.
	var float_item := holding.duplicate()
	float_item["held_item"] = 3.0
	var refused := {2: _avatar(), 5: float_item}
	assert_bool(encoder.payload(refused).is_empty()).is_true()
	assert_int(_errors.count()).is_equal(1)
	assert_bool(_schema.encode(_message(41, refused)).is_empty()).is_true()


func test_what_the_codec_refuses_is_refused_and_logged() -> void:
	var encoder := SnapshotEncoder.new(_schema)
	encoder.start(7)
	var broken := _avatar()
	broken["velocity"] = Vector3(NAN, 0, 0)
	var undeclared := _avatar()
	undeclared["health"] = 100
	var too_many := {}
	for peer in range(1, WireSchema.MAX_AVATARS + 2):
		too_many[peer] = _avatar()
	for avatars: Dictionary in [
		{2: broken}, {2: undeclared}, {0: _avatar()}, {"2": _avatar()}, {2: 1}, too_many
	]:
		_errors.clear()
		assert_bool(encoder.payload(avatars).is_empty()).is_true()
		assert_int(_errors.count()).is_equal(1)
	# A tick the wire cannot carry refuses every payload of that tick.
	encoder.start(0x100000000)
	_errors.clear()
	assert_bool(encoder.payload({2: _avatar()}).is_empty()).is_true()
	assert_bool(encoder.payload({}).is_empty()).is_true()
	assert_int(_errors.count()).is_equal(1)
	# The next tick encodes again.
	encoder.start(8)
	assert_bool(encoder.payload({2: _avatar()}) == _encoded(8, {2: _avatar()})).is_true()
	assert_bool(encoder.payload({}) == _encoded(8, {})).is_true()


## A round of PlayerColours.COUNT players, the most a mode holds.
func _full_round() -> Match:
	var peers: Array[int] = []
	for peer in range(1, PlayerColours.COUNT + 1):
		peers.append(peer)
	var mode := FixtureModes.basic()
	mode.max_players = peers.size()
	var game := Match.new(mode, 7, FlatWorldQuery.new(), FixtureModes.layouts(peers.size()))
	assert_array(Array(game.refusals)).is_empty()
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	FixtureModes.run_ticks(game, 1)
	assert_str(str(game.phase_id())).is_equal("round")
	return game


static func _avatar() -> Dictionary:
	return {
		"position": Vector3(1, 0, 2),
		"velocity": Vector3.ZERO,
		"facing": Vector3(0, 0, -1),
		"downed": false,
		"invulnerable": false,
		"crouched": false,
		"sneaking": false,
		"held_item": -1,
		"belt_item": -1,
	}


func _message(tick: int, avatars: Dictionary) -> WireMessage:
	return WireMessage.new(&"Snapshot", {"tick": tick, "avatars": avatars})


func _encoded(tick: int, avatars: Dictionary) -> PackedByteArray:
	return _schema.encode(_message(tick, avatars))


func _decoded(payload: PackedByteArray) -> Dictionary:
	var decoded := _schema.decode(_schema.kind_of(&"Snapshot"), payload)
	assert_object(decoded).is_not_null()
	return decoded.fields["avatars"] if decoded != null else {}
