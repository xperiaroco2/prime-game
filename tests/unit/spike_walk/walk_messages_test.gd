extends GdUnitTestSuite
## Spike (#14): the walk spike's message schemas decode their own output and reject malformed bytes.

const M := preload("res://spike/walk/walk_messages.gd")


func test_move_round_trips() -> void:
	var msg := M.decode(M.encode_move(3, Vector3(1.5, 0.9, -2.0), 0.75))
	assert_array(msg).is_equal([M.KIND_MOVE, 3, Vector3(1.5, 0.9, -2.0), 0.75])


func test_place_round_trips() -> void:
	var msg := M.decode(M.encode_place(2, Vector3(4, 1, 0)))
	assert_array(msg).is_equal([M.KIND_PLACE, 2, Vector3(4, 1, 0)])


func test_snapshot_round_trips() -> void:
	var ids := PackedInt32Array([5, 9])
	var positions := PackedVector3Array([Vector3(1, 0, 1), Vector3(-1, 0, 2)])
	var yaws := PackedFloat32Array([0.5, -1.0])
	var msg := M.decode(M.encode_snapshot(40, ids, positions, yaws))
	assert_array(msg).is_equal([M.KIND_SNAPSHOT, 40, ids, positions, yaws])


func test_rejects_trailing_bytes() -> void:
	var bytes := M.encode_move(1, Vector3.ZERO, 0.0)
	bytes.append_array(PackedByteArray([0, 0, 0, 0]))
	# bytes_to_var alone ignores the tail, so only decode's size check rejects it.
	assert_int(typeof(bytes_to_var(bytes))).is_equal(TYPE_ARRAY)
	assert_array(M.decode(bytes)).is_empty()


func test_rejects_wrong_field_types() -> void:
	assert_array(M.decode(var_to_bytes([M.KIND_MOVE, 1, Vector2.ZERO, 0.0]))).is_empty()
	assert_array(M.decode(var_to_bytes([M.KIND_MOVE, 1.0, Vector3.ZERO, 0.0]))).is_empty()
	assert_array(M.decode(var_to_bytes([M.KIND_PLACE, 1, Vector3.ZERO, 0]))).is_empty()
	assert_array(M.decode(var_to_bytes([99, 1, Vector3.ZERO]))).is_empty()
	assert_array(M.decode(var_to_bytes("hello"))).is_empty()
	assert_array(M.decode(PackedByteArray())).is_empty()


func test_rejects_non_finite_values() -> void:
	assert_array(M.decode(M.encode_move(1, Vector3(NAN, 0, 0), 0.0))).is_empty()
	assert_array(M.decode(M.encode_move(1, Vector3.ZERO, INF))).is_empty()
	var yaws := PackedFloat32Array([NAN])
	var snap := M.encode_snapshot(
		1, PackedInt32Array([2]), PackedVector3Array([Vector3.ZERO]), yaws
	)
	assert_array(M.decode(snap)).is_empty()


func test_rejects_mismatched_snapshot_arrays() -> void:
	var positions := PackedVector3Array([Vector3.ZERO])
	var snap := M.encode_snapshot(
		1, PackedInt32Array([2, 3]), positions, PackedFloat32Array([0, 0])
	)
	assert_array(M.decode(snap)).is_empty()


func test_rejects_oversized_bytes() -> void:
	var bytes := PackedByteArray()
	bytes.resize(M.MAX_BYTES + 1)
	assert_array(M.decode(bytes)).is_empty()
