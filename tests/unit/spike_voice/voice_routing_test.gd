extends GdUnitTestSuite
## Spike (#15): the host's distance rule decides who hears whom.

const R := preload("res://spike/voice/voice_routing.gd")


func _positions() -> Dictionary[int, Vector3]:
	return {
		2: Vector3(0, 1, 0),
		5: Vector3(3, 1, 4),  # 5 m from 2
		9: Vector3(0, 1, 8),  # exactly 8 m from 2
		12: Vector3(0, 1, -8.01),  # just past 8 m from 2
	}


func test_listeners_within_cutoff_in_id_order() -> void:
	var r := R.new()
	r.cutoff = 8.0
	assert_array(Array(r.listeners_of(2, _positions()))).is_equal([5, 9])


func test_cutoff_is_inclusive_and_symmetric() -> void:
	var r := R.new()
	r.cutoff = 8.0
	assert_bool(r.hears(Vector3(0, 1, 0), Vector3(0, 1, 8))).is_true()
	assert_bool(r.hears(Vector3(0, 1, 8), Vector3(0, 1, 0))).is_true()
	assert_bool(r.hears(Vector3(0, 1, 0), Vector3(0, 1, 8.01))).is_false()


func test_speaker_never_hears_itself_and_unplaced_speaker_reaches_no_one() -> void:
	var r := R.new()
	assert_bool(Array(r.listeners_of(5, _positions())).has(5)).is_false()
	assert_array(Array(r.listeners_of(77, _positions()))).is_empty()


func test_smaller_cutoff_drops_farther_listeners() -> void:
	var r := R.new()
	r.cutoff = 5.0
	assert_array(Array(r.listeners_of(2, _positions()))).is_equal([5])
	assert_array(Array(r.listeners_of(9, _positions()))).is_equal([5])
	assert_array(Array(r.listeners_of(12, _positions()))).is_empty()
