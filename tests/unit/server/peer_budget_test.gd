extends GdUnitTestSuite
## PeerBudget (ARCHITECTURE §4.5 "Rate limits", E7): three buckets, refilled for the host time
## elapsed, and voice apart from the reliable intents.

const SECOND := 1000000


func test_each_bucket_starts_full_and_empties() -> void:
	var budget := PeerBudget.new()
	for _i in int(PeerBudget.VOICE_FRAMES):
		assert_bool(budget.take_voice()).is_true()
	assert_bool(budget.take_voice()).is_false()
	for _i in int(PeerBudget.INTENTS):
		assert_bool(budget.take_intent(5)).is_true()
	assert_bool(budget.take_intent(5)).is_false()
	assert_bool(budget.take_bytes(int(PeerBudget.BYTES) - 500)).is_true()
	assert_bool(budget.take_bytes(1)).is_false()


func test_voice_never_drains_the_intents() -> void:
	var budget := PeerBudget.new()
	while budget.take_voice():
		pass
	assert_bool(budget.take_intent(5)).is_true()
	assert_float(budget.bytes).is_equal(PeerBudget.BYTES - 5)


func test_an_intent_takes_its_bytes_too_or_nothing() -> void:
	var budget := PeerBudget.new()
	assert_bool(budget.take_bytes(int(PeerBudget.BYTES) - 3)).is_true()
	assert_bool(budget.take_intent(5)).is_false()
	assert_float(budget.intents).is_equal(PeerBudget.INTENTS)
	assert_bool(budget.take_intent(3)).is_true()
	assert_float(budget.intents).is_equal(PeerBudget.INTENTS - 1)


func test_refill_follows_the_time_and_stops_at_the_size() -> void:
	var budget := PeerBudget.new()
	while budget.take_intent(1):
		pass
	budget.refill(SECOND / 2)
	assert_float(budget.intents).is_equal_approx(PeerBudget.INTENTS_PER_SECOND / 2, 1e-6)
	budget.refill(60 * SECOND)
	assert_float(budget.intents).is_equal(PeerBudget.INTENTS)
	assert_float(budget.voice_frames).is_equal(PeerBudget.VOICE_FRAMES)
	assert_float(budget.bytes).is_equal(PeerBudget.BYTES)
	budget.refill(-SECOND)
	assert_float(budget.intents).is_equal(PeerBudget.INTENTS)


func test_each_bucket_holds_ten_seconds_of_an_honest_client() -> void:
	# 50 voice frames, a few intents and about 1 KB of claims per second (§4.5).
	assert_float(PeerBudget.VOICE_FRAMES).is_greater_equal(10 * 50.0)
	assert_float(PeerBudget.INTENTS).is_greater(10 * 5.0)
	assert_float(PeerBudget.BYTES).is_greater(10 * 1024.0)
