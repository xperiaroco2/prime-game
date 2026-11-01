extends GdUnitTestSuite
## BoothReplay on the wire (ARCHITECTURE §4.3.4 row 97, #1474): a reliable host-to-client row whose
## cap is its size at the maxima, which round-trips in the decoder's types (a list of lists); its
## frame count is core's, and one frame more is refused.

const Samples := preload("res://tests/unit/net/messages/wire_samples.gd")
const EngineErrors := preload("res://tests/unit/net/messages/engine_errors.gd")
const REPLAY := 97

var _schema: WireSchema
var _errors: EngineErrors


func before_test() -> void:
	_schema = WireSchema.game(true)
	_errors = EngineErrors.new()
	_errors.start()


func after_test() -> void:
	_errors.stop()


func test_the_row_is_a_reliable_event_to_the_client_capped_at_its_size() -> void:
	var row := _schema.row_named(&"BoothReplay")
	assert_int(_schema.kind_of(&"BoothReplay")).is_equal(REPLAY)
	assert_int(row.direction).is_equal(NetKindTable.Direction.HOST_TO_CLIENT)
	assert_int(row.lane).is_equal(NetKindTable.Lane.RELIABLE)
	assert_int(row.cap).is_equal(row.max_size())
	assert_int(row.cap).is_less_equal(_schema.row_named(&"Welcome").cap)


func test_the_wire_takes_as_many_frames_as_core_shoots() -> void:
	assert_int(WireSchema.MAX_BOOTH_FRAMES).is_equal(StartBooth.MAX_FRAMES)
	assert_int(WireSchema.VERSION).is_equal(JoinRules.PROTOCOL_VERSION)


func test_the_largest_replay_round_trips_under_the_cap() -> void:
	var fields := Samples.booth_replay_at_maxima().to_dict()
	var payload := _schema.encode(WireMessage.new(&"BoothReplay", fields))
	assert_int(payload.size()).is_equal(_schema.row_named(&"BoothReplay").cap)
	var decoded := _schema.decode(REPLAY, payload)
	assert_object(decoded).override_failure_message(_schema.explain(REPLAY, payload)).is_not_null()
	if decoded == null:
		return
	assert_bool(Samples.same(decoded.fields, fields)).is_true()
	assert_int(_errors.count()).is_equal(0)


func test_one_frame_more_is_refused() -> void:
	var over := Samples.booth_replay_at_maxima()
	over.records.append([] as Array[Dictionary])
	var logged := _errors.count()
	assert_int(_schema.encode(WireMessage.new(&"BoothReplay", over.to_dict())).size()).is_equal(0)
	assert_int(_errors.count()).is_equal(logged + 1)
	_errors.clear()
