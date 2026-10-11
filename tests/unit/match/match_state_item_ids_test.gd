extends GdUnitTestSuite
## MatchState's item ids (ARCHITECTURE §9.1, §9.3; the cooking ADR, CE3, §7): add_item hands out
## new ids from its counter up to MAX_ITEM_ID, the wire's limit, and only then the id remove_item
## freed longest ago, never one in use; reset_match() puts the counter back to 1 and empties the
## queue, so no match inherits ids another freed.

const LIMIT := MatchState.MAX_ITEM_ID


func test_below_the_limit_an_id_is_always_new() -> void:
	var state := MatchState.new(1)
	var kind := ItemKind.new()
	var first := state.add_item(kind, Vector3.ZERO)
	var second := state.add_item(kind, Vector3.ONE)
	assert_int(first.id).is_equal(1)
	assert_int(second.id).is_equal(2)
	state.remove_item(first.id)
	assert_bool(state.items.has(first.id)).is_false()
	assert_int(state.add_item(kind, Vector3.ZERO).id).is_equal(3)


func test_past_the_limit_the_id_freed_longest_ago_is_reused() -> void:
	var state := MatchState.new(1)
	var kind := ItemKind.new()
	state.skip_item_ids_to(LIMIT - 3)
	var ids: Array[int] = []
	for i in 4:
		ids.append(state.add_item(kind, Vector3.ZERO).id)
	assert_array(ids).is_equal([LIMIT - 3, LIMIT - 2, LIMIT - 1, LIMIT])
	# Every id in use: no new item.
	assert_object(state.add_item(kind, Vector3.ZERO)).is_null()
	# Freed out of id order; an id that is no item frees nothing.
	state.remove_item(LIMIT - 1)
	state.remove_item(LIMIT - 3)
	state.remove_item(LIMIT - 3)
	state.remove_item(LIMIT)
	state.remove_item(5)
	var reused: Array[int] = []
	for i in 3:
		reused.append(state.add_item(kind, Vector3.ZERO).id)
	assert_array(reused).is_equal([LIMIT - 1, LIMIT - 3, LIMIT])
	assert_object(state.add_item(kind, Vector3.ZERO)).is_null()
	assert_int(state.items.size()).is_equal(4)


func test_the_counter_is_skipped_forward_only_and_never_past_the_limit() -> void:
	var state := MatchState.new(1)
	var kind := ItemKind.new()
	state.skip_item_ids_to(10)
	state.skip_item_ids_to(3)
	assert_int(state.add_item(kind, Vector3.ZERO).id).is_equal(10)
	state.skip_item_ids_to(LIMIT + 50)
	assert_object(state.add_item(kind, Vector3.ZERO)).is_null()


func test_a_reset_match_hands_out_ids_from_1_and_never_a_queued_one() -> void:
	var state := MatchState.new(1)
	var kind := ItemKind.new()
	state.skip_item_ids_to(LIMIT - 1)
	state.add_item(kind, Vector3.ZERO)
	state.add_item(kind, Vector3.ZERO)
	state.remove_item(LIMIT)
	state.remove_item(LIMIT - 1)
	state.reset_match()
	assert_int(state.add_item(kind, Vector3.ZERO).id).is_equal(1)
	assert_int(state.add_item(kind, Vector3.ZERO).id).is_equal(2)
	# Up to the limit and past it: the queue the last match filled is gone.
	state.skip_item_ids_to(LIMIT + 1)
	assert_object(state.add_item(kind, Vector3.ZERO)).is_null()
