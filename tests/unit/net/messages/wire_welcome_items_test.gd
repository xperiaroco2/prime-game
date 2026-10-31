extends GdUnitTestSuite
## Welcome's item rows on the wire (ARCHITECTURE §4.3.4 row 33, #1404): the most rows round-trip
## in the decoder's types, one more is refused by the encoder and rejected by the decoder, a cut
## row is rejected, and the wire's maximum is core's.

const Samples := preload("res://tests/unit/net/messages/wire_samples.gd")
const EngineErrors := preload("res://tests/unit/net/messages/engine_errors.gd")
const WELCOME := 33

var _schema: WireSchema
var _errors: EngineErrors


func before_test() -> void:
	_schema = WireSchema.game(true)
	_errors = EngineErrors.new()
	_errors.start()


func after_test() -> void:
	_errors.stop()


func test_the_wire_takes_as_many_rows_as_core_sends() -> void:
	assert_int(WireSchema.MAX_WELCOME_ITEMS).is_equal(WelcomeEvent.MAX_ITEMS)
	assert_int(_schema.kind_of(&"Welcome")).is_equal(WELCOME)


func test_the_most_rows_of_the_longest_kind_round_trip_under_the_cap() -> void:
	var fields := _fields(WireSchema.MAX_WELCOME_ITEMS)
	var payload := _schema.encode(WireMessage.new(&"Welcome", fields))
	assert_int(payload.size()).is_greater(0)
	assert_int(payload.size()).is_less_equal(_schema.row_named(&"Welcome").cap)
	var decoded := _schema.decode(WELCOME, payload)
	assert_object(decoded).override_failure_message(_schema.explain(WELCOME, payload)).is_not_null()
	if decoded == null:
		return
	assert_bool(Samples.same(decoded.fields["items"], fields["items"])).is_true()
	assert_int(_errors.count()).is_equal(0)


func test_one_row_more_is_refused_and_rejected() -> void:
	var over := _fields(WireSchema.MAX_WELCOME_ITEMS + 1)
	var logged := _errors.count()
	assert_int(_schema.encode(WireMessage.new(&"Welcome", over)).size()).is_equal(0)
	assert_int(_errors.count()).is_equal(logged + 1)
	_errors.clear()
	# The decoder: the full list's count raised by one. The payloads with the list full and empty
	# agree up to that count, the last field's.
	var full := _schema.encode(WireMessage.new(&"Welcome", _fields(WireSchema.MAX_WELCOME_ITEMS)))
	var empty := _schema.encode(WireMessage.new(&"Welcome", _fields(0)))
	var at := 0
	while at < empty.size() and full[at] == empty[at]:
		at += 1
	assert_int(full[at]).is_equal(WireSchema.MAX_WELCOME_ITEMS)
	full[at] = WireSchema.MAX_WELCOME_ITEMS + 1
	assert_object(_schema.decode(WELCOME, full)).is_null()
	assert_str(_schema.explain(WELCOME, full)).contains("97 entries, at most 96")


func test_a_cut_row_is_rejected() -> void:
	var payload := _schema.encode(WireMessage.new(&"Welcome", _fields(3)))
	for cut: int in [1, 6, 13]:
		var short := payload.slice(0, payload.size() - cut)
		assert_object(_schema.decode(WELCOME, short)).override_failure_message(str(cut)).is_null()


## The sample Welcome with `count` rows: the sample's own rows, then rows of a 32-character kind.
func _fields(count: int) -> Dictionary:
	var welcome := Samples.events()["WelcomeEvent"][0] as WelcomeEvent
	var rows := Samples.welcome_items()
	rows.resize(mini(rows.size(), count))
	while rows.size() < count:
		(
			rows
			. append(
				{
					"item": rows.size() + 100,
					"kind": StringName(Samples.ID_32),
					"where": 3,
					"holder": 0x7FFFFFFF,
					"place": 2,
					"position": Vector3(-1.5, 2.25, 1e6),
				}
			)
		)
	welcome.items = rows
	return welcome.to_dict()
