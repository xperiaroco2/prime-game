extends GdUnitTestSuite
## Every decoder fed broken input (ARCHITECTURE §4.4): every truncation, every single-byte change
## and random payloads of every row. Each must be a clean reject, or a message the encoder writes
## back byte for byte (a changed float or id is still a valid message), and no engine error line
## may be printed: decode_* past the end would print one, which a peer could repeat at will.

const Samples := preload("res://tests/unit/net/messages/wire_samples.gd")
const EngineErrors := preload("res://tests/unit/net/messages/engine_errors.gd")
const RANDOM_PAYLOADS_PER_ROW := 300

var _schema: WireSchema
var _errors: EngineErrors
var _failures := PackedStringArray()


func before_test() -> void:
	_schema = WireSchema.game(true)
	_errors = EngineErrors.new()
	_errors.start()
	_failures.clear()


func after_test() -> void:
	_errors.stop()


func test_every_truncation_is_rejected() -> void:
	var checked := 0
	for message: WireMessage in Samples.all_messages():
		var kind := _schema.kind_of(message.name)
		var payload := _schema.encode(message)
		var last: WireField = _schema.row(kind).fields.back()
		var ends_with_opus := last.type == WireField.Type.OPUS
		for size: int in payload.size():
			var cut := payload.slice(0, size)
			if ends_with_opus:
				_assert_rejected_or_canonical(kind, cut)
			elif _schema.decode(kind, cut) != null:
				_failures.append("%s cut to %d bytes decoded" % [message.name, size])
			checked += 1
	assert_int(checked).is_greater(1500)
	assert_array(Array(_failures)).is_empty()
	assert_array(Array(_errors.snapshot())).is_empty()


func test_every_single_byte_change_is_rejected_or_canonical() -> void:
	var checked := 0
	for message: WireMessage in Samples.all_messages():
		var kind := _schema.kind_of(message.name)
		var payload := _schema.encode(message)
		# An Opus frame is opaque: the codec reads none of its bytes, so one change each is enough.
		var frame: PackedByteArray = message.fields.get("opus", PackedByteArray())
		var opaque_from := payload.size() - frame.size()
		for at: int in payload.size():
			var original := payload[at]
			var values: Array = range(256) if at < opaque_from else [original ^ 0xFF]
			for value: int in values:
				if value == original:
					continue
				payload[at] = value
				_assert_rejected_or_canonical(kind, payload)
				checked += 1
			payload[at] = original
	assert_int(checked).is_greater(100000)
	assert_array(Array(_failures)).is_empty()
	assert_array(Array(_errors.snapshot())).is_empty()


func test_random_payloads_are_rejected_or_canonical() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 98
	var accepted := 0
	for each: WireRow in _schema.rows():
		for i: int in RANDOM_PAYLOADS_PER_ROW:
			var size := random.randi_range(0, mini(each.cap, 64 if i % 2 == 0 else each.cap))
			var payload := PackedByteArray()
			payload.resize(size)
			for at: int in size:
				payload[at] = random.randi_range(0, 255)
			if _assert_rejected_or_canonical(each.kind, payload):
				accepted += 1
	assert_int(accepted).is_greater(0)
	assert_array(Array(_failures)).is_empty()
	assert_array(Array(_errors.snapshot())).is_empty()


func test_the_error_log_catches_an_engine_error() -> void:
	# The suites above trust this logger: show it sees an engine error line from decode_*.
	var bytes := PackedByteArray([1, 2])
	bytes.decode_u32(0)
	assert_int(_errors.count()).is_greater(0)
	_errors.clear()


## True when the payload decoded; then the encoder must write the same bytes back, or the
## problem goes into _failures (asserted once per test: an assert per payload is slow).
func _assert_rejected_or_canonical(kind: int, payload: PackedByteArray) -> bool:
	var decoded := _schema.decode(kind, payload)
	if decoded == null:
		return false
	if kind == WireSchema.HELLO and decoded.fields["version"] != WireSchema.VERSION:
		if decoded.fields.size() != 1:
			_failures.append("kind 1 %s: more than the version" % payload)
		return true
	var again := _schema.write(decoded)
	if not again.problem.is_empty():
		_failures.append(
			"kind %d %s decoded but did not encode: %s" % [kind, payload, again.problem]
		)
	elif again.payload != payload:
		_failures.append("kind %d %s re-encoded as %s" % [kind, payload, again.payload])
	return true
