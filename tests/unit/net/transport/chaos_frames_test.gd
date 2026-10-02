extends GdUnitTestSuite
## The chaos bots' malformed frames (ChaosFrames, #188) over a LoopbackHub, as the host's transport
## and the codec take them (ARCHITECTURE §4 Transport, §4.3, §4.4): each shape a NetFrame reject is
## counted under its reason, with nothing delivered; each shape the codec rejects passes NetFrame
## and fails decoding (or is a debug kind, which only peer 1 may send, E17). So the chaos run's
## expectations come from the rules, and a shape that stops meaning what it says fails here.

const PORT := 7360
const SAMPLES := 12

var _schema := WireSchema.game(true)
var _hub: LoopbackHub
var _host: LoopbackTransport
var _client: ChaosLoopback
var _delivered: Array[Array] = []
var _rejected: Array[int] = []


func before_test() -> void:
	_hub = LoopbackHub.new()
	_host = LoopbackTransport.new(_schema.kind_table(), _hub)
	assert_int(_host.host(PORT, 4)).is_equal(OK)
	_host.packet_received.connect(
		func(_peer: int, kind: int, payload: PackedByteArray) -> void:
			_delivered.append([kind, payload])
	)
	_host.packet_rejected.connect(
		func(_peer: int, reason: NetRejects.Reason) -> void: _rejected.append(reason)
	)
	_client = ChaosLoopback.new(_schema.kind_table(), _hub)
	_client.join("loopback", PORT)
	_host.poll()
	_client.poll()
	_delivered.clear()
	_rejected.clear()


func after_test() -> void:
	_client.close()
	_host.close()


func test_each_malformed_shape_is_rejected_under_its_reason_and_nothing_else() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 188
	for shape: int in ChaosFrames.Shape.values():
		for _i in SAMPLES:
			_delivered.clear()
			_rejected.clear()
			var packet := ChaosFrames.malformed(
				shape as ChaosFrames.Shape, rng, _schema, _client.own_id()
			)
			assert_bool(_client.send_raw(packet)).is_true()
			_host.poll()
			var label := packet.label
			if not packet.frame_valid:
				assert_array(_rejected).override_failure_message(label).is_equal([packet.expect])
				assert_array(_delivered).override_failure_message(label).is_empty()
				continue
			assert_int(packet.expect).is_equal(NetRejects.Reason.BAD_PAYLOAD)
			assert_array(_rejected).override_failure_message(label).is_empty()
			assert_int(_delivered.size()).override_failure_message(label).is_equal(1)
			var kind: int = _delivered[0][0]
			var debug_kind := kind >= WireSchema.FIRST_DEBUG and kind < WireSchema.FIRST_EVENT
			var decoded := _schema.decode(kind, _delivered[0][1] as PackedByteArray)
			assert_bool(debug_kind or decoded == null).override_failure_message(label).is_true()


func test_a_hostile_claim_decodes_with_its_tag_and_an_honest_one_has_none() -> void:
	for shape: int in ChaosFrames.Claim.values():
		var packet := ChaosFrames.claim(
			shape as ChaosFrames.Claim, _schema, 3, 40, Vector3(1, 0, 2), 5
		)
		var payload := packet.bytes.slice(NetFrame.HEADER_BYTES)
		var decoded := _schema.decode(_schema.kind_of(&"MoveClaim"), payload)
		assert_object(decoded).is_not_null()
		assert_int(ChaosFrames.claim_shape(decoded.fields)).is_equal(shape)
	assert_int(ChaosFrames.claim_shape({"velocity": Vector3(4, 0, 0)})).is_equal(-1)


func test_a_hostile_claim_carries_an_honest_walkers_masks_at_the_v7_layout() -> void:
	# Protocol v7 (#155): the masks follow jumps, so the offsets NAN_CLAIM, INF_CLAIM and FLAG_BITS
	# break stay those of the first float and the flags.
	var packet := ChaosFrames.claim(ChaosFrames.Claim.SPEED, _schema, 2, 9, Vector3(1, 0, 2), 4)
	var payload := packet.bytes.slice(NetFrame.HEADER_BYTES)
	var kind := _schema.kind_of(&"MoveClaim")
	assert_int(payload.size()).is_equal(_schema.row(kind).cap)
	var fields := _schema.decode(kind, payload).fields
	assert_int(fields["sprint_ticks"] as int).is_equal(0)
	# The wire row's u32 maximum, written out: a change of MovementRule.MAX_MASK shows here.
	assert_int(fields["moved_ticks"] as int).is_equal(0xFFFFFFFF)
	assert_float(payload.decode_float(ChaosFrames.CLAIM_FLOATS_AT)).is_equal(1.0)
	var last_float := ChaosFrames.CLAIM_FLOATS_AT + 4 * (ChaosFrames.CLAIM_FLOATS - 1)
	# The harness writes facing Vector3.FORWARD, so the last float is its z.
	assert_float(payload.decode_float(last_float)).is_equal(Vector3.FORWARD.z)
	# The flags byte: moving and on_floor set, sprint clear (sprint, moving, on_floor from bit 0).
	assert_int(payload[ChaosFrames.CLAIM_FLAGS_AT]).is_equal(0b110)


func test_everything_a_chaos_transport_sends_is_in_its_outbox_in_order() -> void:
	var set_ready := ChaosFrames.message(_schema, &"SetReady", {"ready": true}, 5)
	var payload := set_ready.bytes.slice(NetFrame.HEADER_BYTES)
	assert_int(_client.send(NetTransport.HOST_ID, _schema.kind_of(&"SetReady"), payload)).is_equal(
		OK
	)
	var raw := ChaosFrames.malformed(
		ChaosFrames.Shape.TOO_SHORT, RandomNumberGenerator.new(), _schema, 2
	)
	assert_bool(_client.send_raw(raw)).is_true()
	var sent := _client.take_outbox()
	assert_int(sent.size()).is_equal(2)
	assert_str(sent[0].label).is_equal("honest")
	assert_bool(sent[0].frame_valid).is_true()
	assert_object(sent[1]).is_same(raw)
	assert_array(_client.take_outbox()).is_empty()
