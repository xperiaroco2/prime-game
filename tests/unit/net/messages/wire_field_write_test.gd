extends GdUnitTestSuite
## WireField's write path after #1234: keys() built once, the undeclared-key rule counted through
## them, and each map key checked and written once; the problems named as before.


func test_keys_are_built_once_and_an_optionals_are_its_parts() -> void:
	var guarded: Array[WireField] = [
		WireField.of("a", WireField.Type.U8), WireField.bits(["b", "c"])
	]
	var optional := WireField.when("has_a", guarded)
	assert_array(Array(optional.keys())).contains_exactly(["a", "b", "c"])
	assert_array(Array(optional.keys())).contains_exactly(["a", "b", "c"])
	assert_array(Array(WireField.seq_number().keys())).is_empty()


func test_an_undeclared_key_is_named_whatever_its_type() -> void:
	var fields: Array[WireField] = [WireField.of("a", WireField.Type.U8)]
	assert_str(_write(fields, {"a": 1})).is_empty()
	assert_str(_write(fields, {&"a": 1})).is_empty()
	assert_str(_write(fields, {"a": 1, "b": 2})).is_equal("an undeclared field b")
	assert_str(_write(fields, {"a": 1, &"b": 2})).is_equal("an undeclared field b")
	assert_str(_write(fields, {"a": 1, 7: 2})).is_equal("an undeclared field 7")
	var record: Array[WireField] = [WireField.record("r", fields)]
	assert_str(_write(record, {"r": {"a": 1, "z": 0}})).is_equal("an undeclared field z")


func test_a_maps_keys_are_checked_before_its_values_and_written_in_order() -> void:
	var map := WireField.map(
		"m", WireField.of("", WireField.Type.PEER), WireField.of("", WireField.Type.U8), 4
	)
	var fields: Array[WireField] = [map]
	assert_str(_write(fields, {"m": {2: 300, 0: 1}})).starts_with("m: key ")
	var writer := WireWriter.new()
	assert_str(WireField.write_all(fields, {"m": {300: 3, 2: 1, 17: 2}}, writer, null)).is_empty()
	var expected := PackedByteArray([3])
	for pair: Vector2i in [Vector2i(2, 1), Vector2i(17, 2), Vector2i(300, 3)]:
		var at := expected.size()
		expected.resize(at + 4)
		expected.encode_u32(at, pair.x)
		expected.append(pair.y)
	assert_array(Array(writer.bytes)).is_equal(Array(expected))


func _write(fields: Array[WireField], source: Dictionary) -> String:
	return WireField.write_all(fields, source, WireWriter.new(), null)
