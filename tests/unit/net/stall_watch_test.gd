extends GdUnitTestSuite
## StallWatch: a drop's window judged at the running side's polls, so a hitch that delays the
## poll a drop comes in cannot fail a transport that dropped at its first chance (#443).

const LOW := 9950
const HIGH := 21000
const STALL_AT := 1000


func _watch_polled_every(step_ms: int, until_ms: int) -> StallWatch:
	var watch := StallWatch.new()
	watch.serviced(STALL_AT - step_ms)
	watch.stall(STALL_AT)
	var at := STALL_AT
	while at <= until_ms:
		watch.serviced(at)
		at += step_ms
	return watch


func test_a_drop_inside_the_window_passes() -> void:
	var watch := _watch_polled_every(16, STALL_AT + 19990)
	watch.drop(STALL_AT + 20010)
	assert_bool(watch.dropped()).is_true()
	assert_int(watch.dropped_after_ms()).is_equal(20010)
	assert_str(watch.judge(LOW, HIGH)).is_empty()


## The issue's run: the host's last poll before the drop was inside the window, then a 1.7 s
## hitch; the drop came at the next poll, 21649 ms after the stall.
func test_a_hitch_before_the_drop_poll_is_not_a_late_drop() -> void:
	var watch := _watch_polled_every(16, STALL_AT + 19900)
	watch.drop(STALL_AT + 21649)
	assert_int(watch.dropped_after_ms()).is_equal(21649)
	assert_int(watch.kept_after_ms()).is_less_equal(19900)
	assert_int(watch.hitch_ms()).is_greater_equal(1749)
	assert_str(watch.judge(LOW, HIGH)).is_empty()


## A transport with a longer timeout keeps the stalled side through polls past the top.
func test_a_poll_past_the_top_that_kept_the_peer_fails() -> void:
	var watch := _watch_polled_every(16, STALL_AT + 21100)
	watch.drop(STALL_AT + 21120)
	assert_str(watch.judge(LOW, HIGH)).contains("still had the stalled side")
	assert_str(watch.judge(LOW, HIGH)).contains("21000")


func test_a_drop_under_the_bottom_fails() -> void:
	var watch := _watch_polled_every(16, STALL_AT + 9900)
	watch.drop(STALL_AT + 9930)
	assert_str(watch.judge(LOW, HIGH)).contains("dropped after 9930 ms")


func test_a_hitch_never_makes_an_early_drop_pass() -> void:
	var watch := _watch_polled_every(16, STALL_AT + 2000)
	watch.drop(STALL_AT + 9000)
	assert_str(watch.judge(LOW, HIGH)).contains("under 9950")


func test_polls_after_the_drop_change_nothing() -> void:
	var watch := _watch_polled_every(16, STALL_AT + 15000)
	watch.drop(STALL_AT + 15010)
	watch.serviced(STALL_AT + 30000)
	assert_int(watch.kept_after_ms()).is_less(15010)
	assert_str(watch.judge(LOW, HIGH)).is_empty()


func test_no_drop_fails() -> void:
	var watch := _watch_polled_every(16, STALL_AT + 30000)
	assert_bool(watch.dropped()).is_false()
	assert_str(watch.judge(LOW, HIGH)).contains("never dropped")


func test_a_drop_before_any_stall_fails() -> void:
	var watch := StallWatch.new()
	watch.serviced(500)
	watch.drop(600)
	assert_str(watch.judge(LOW, HIGH)).contains("before the stall")
