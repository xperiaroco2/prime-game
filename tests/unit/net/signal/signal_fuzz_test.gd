extends GdUnitTestSuite
## The signalling decoder fed broken input (ARCHITECTURE §4.8; the M6 ADR §6): every truncation of
## every sample, every field replaced by a value of each other JSON type, oversized and deeply
## nested input, and random bytes. Each must be a clean reject or a valid message whose fields pass
## the codec's own checks again, and no engine error line may be printed: a peer could repeat any
## such line at will.

const Samples := preload("res://tests/unit/net/signal/signal_samples.gd")
const EngineErrors := preload("res://tests/unit/net/messages/engine_errors.gd")
const RANDOM_INPUTS := 3000
const WRONG_VALUES: Array = [
	null, true, false, 0, -1, 1.5, 1e300, "", "x", "ABCDEF", [], [1], {}, {"urls": ["stun:a"]}
]

var _errors: EngineErrors
var _failures := PackedStringArray()


func before_test() -> void:
	_errors = EngineErrors.new()
	_errors.start()
	_failures.clear()


func after_test() -> void:
	_errors.stop()


func test_every_truncation_is_rejected() -> void:
	var checked := 0
	for sample: Array in Samples.all():
		var text := _text_of(sample)
		for size: int in text.length():
			var cut := text.substr(0, size).to_ascii_buffer()
			for side: int in SignalCodec.Side.values():
				if SignalCodec.decode(cut, side).ok():
					_failures.append("%s cut to %d bytes decoded" % [text, size])
				checked += 1
	assert_int(checked).is_greater(5000)
	assert_array(Array(_failures)).is_empty()
	assert_array(Array(_errors.snapshot())).is_empty()


func test_a_field_of_any_wrong_type_is_rejected_or_valid() -> void:
	var checked := 0
	for sample: Array in Samples.all():
		var side: int = sample[0]
		var fields: Dictionary = sample[2]
		for key: String in ["t", "v"] + fields.keys():
			for value: Variant in WRONG_VALUES:
				var message: Dictionary = {"t": sample[1], "v": 1}
				message.merge(fields)
				message[key] = value
				_check(JSON.stringify(message).to_ascii_buffer(), side)
				message.erase(key)
				_check(JSON.stringify(message).to_ascii_buffer(), side)
				checked += 2
	assert_int(checked).is_greater(1000)
	assert_array(Array(_failures)).is_empty()
	assert_array(Array(_errors.snapshot())).is_empty()


func test_oversized_and_deep_input_is_rejected() -> void:
	for size: int in [SignalCodec.MAX_MESSAGE_BYTES + 1, 65536, 1 << 20]:
		var big := PackedByteArray()
		big.resize(size)
		big.fill(0x20)
		_expect_rejected(big, SignalCodec.WHY_TOO_LARGE)
	var huge_sdp := '{"t": "answer", "v": 1, "sdp": "%s"}' % "a".repeat(SignalCodec.MAX_SDP + 1)
	_expect_rejected(huge_sdp.to_ascii_buffer(), SignalCodec.WHY_BAD, [SignalCodec.Side.JOINER])
	for depth: int in [100, 600, 5000]:
		_check(("[".repeat(depth) + "]".repeat(depth)).to_ascii_buffer(), SignalCodec.Side.HOST)
		var nested := '{"t": "close", "v": 1, "x": %s}' % ("[".repeat(depth) + "]".repeat(depth))
		_check(nested.to_ascii_buffer(), SignalCodec.Side.HOST)
	var servers := []
	for i: int in SignalCodec.MAX_ICE_SERVERS + 1:
		servers.append({"urls": ["stun:a"]})
	var room := {"t": "room", "v": 1, "code": "ABCDEF", "ice_servers": servers}
	var to_host: Array = [SignalCodec.Side.TO_HOST]
	_expect_rejected(JSON.stringify(room).to_ascii_buffer(), SignalCodec.WHY_BAD, to_host)
	assert_array(Array(_failures)).is_empty()
	assert_array(Array(_errors.snapshot())).is_empty()


func test_random_bytes_and_random_json_are_rejected_or_valid() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 366
	var samples := Samples.all()
	for i: int in RANDOM_INPUTS:
		var bytes := PackedByteArray()
		if i % 4 == 0:
			bytes.resize(random.randi_range(0, 64))
			for at: int in bytes.size():
				bytes[at] = random.randi_range(0, 255)
		elif i % 4 == 1:
			# Printable ASCII, which passes the byte check and reaches the JSON parser.
			bytes.resize(random.randi_range(0, 64))
			for at: int in bytes.size():
				bytes[at] = random.randi_range(0x20, 0x7E)
		else:
			# A sample with a few bytes changed to printable ASCII: mostly still JSON.
			bytes = _text_of(samples[random.randi_range(0, samples.size() - 1)]).to_ascii_buffer()
			for change: int in random.randi_range(1, 3):
				bytes[random.randi_range(0, bytes.size() - 1)] = random.randi_range(0x20, 0x7E)
		for side: int in SignalCodec.Side.values():
			_check(bytes, side)
	assert_array(Array(_failures)).is_empty()
	assert_array(Array(_errors.snapshot())).is_empty()


## \u escapes the byte check cannot see: lone and paired surrogates, NUL, non-ASCII letters.
func test_unicode_escapes_are_rejected_without_an_error_line() -> void:
	for escape: String in ["\\ud800", "\\udc00", "\\ud83d\\ude00", "\\u0000", "\\u00e9", "\\uffff"]:
		var text := '{"t": "candidate", "v": 1, "mid": "0", "index": 0, "cand": "a%s"}' % escape
		_expect_rejected(text.to_ascii_buffer(), SignalCodec.WHY_BAD, [SignalCodec.Side.JOINER])
		var key := '{"t": "close", "v": 1, "%s": 1}' % escape
		_check(key.to_ascii_buffer(), SignalCodec.Side.HOST)
	assert_array(Array(_failures)).is_empty()
	assert_array(Array(_errors.snapshot())).is_empty()


## A result must be a reject with a reason, or a message of a type of that side whose fields
## encode and decode back unchanged.
func _check(bytes: PackedByteArray, side: int) -> void:
	var decoded := SignalCodec.decode(bytes, side)
	if not decoded.ok():
		if decoded.type != "" or not decoded.fields.is_empty():
			_failures.append("a reject kept its fields: %s" % bytes.hex_encode())
		return
	var types: Dictionary = SignalCodec.TYPES[side]
	if not types.has(decoded.type):
		_failures.append("side %d accepted %s" % [side, decoded.type])
		return
	var again := SignalCodec.decode(
		JSON.stringify(SignalCodec.as_message(decoded)).to_ascii_buffer(), side
	)
	if not again.ok() or again.fields != decoded.fields:
		_failures.append("not canonical: %s" % bytes.hex_encode())


## Rejected for `why` from each of `sides` (every side when empty).
func _expect_rejected(bytes: PackedByteArray, why: String, sides: Array = []) -> void:
	for side: int in sides if not sides.is_empty() else SignalCodec.Side.values():
		var got := SignalCodec.decode(bytes, side).why
		if got != why:
			_failures.append("side %d: expected %s, got '%s'" % [side, why, got])


func _text_of(sample: Array) -> String:
	var message: Dictionary = {"t": sample[1], "v": 1}
	var fields: Dictionary = sample[2]
	message.merge(fields)
	return JSON.stringify(message)
