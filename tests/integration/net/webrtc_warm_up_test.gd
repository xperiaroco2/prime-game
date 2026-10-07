extends GdUnitTestSuite
## WebRtcWarmUp.wait() (#510): the blocking wait of the runs that do nothing else before their
## first host or join. A real warm-up comes back ready; one whose offer never comes stops at its
## bound and names the cause.

const WebRtcWarmUp := preload("res://tests/integration/net/webrtc_warm_up.gd")
## The bound of the never-ready warm-up: short, so the test is quick.
const SHORT_MS := 50


## A warm-up whose offer never comes: the wait's timeout without a hung library.
class NeverReady:
	extends "res://tests/integration/net/webrtc_warm_up.gd"

	func is_ready() -> bool:
		return false


func test_wait_returns_once_the_library_is_set_up() -> void:
	var warm_up := WebRtcWarmUp.new()
	var ready := warm_up.wait()
	assert_str(warm_up.error_text).is_empty()
	assert_bool(ready).is_true()
	assert_bool(warm_up.is_ready()).is_true()
	assert_int(warm_up.error).is_equal(OK)
	warm_up.close()


func test_wait_gives_up_after_its_bound_and_names_the_cause() -> void:
	var warm_up := NeverReady.new()
	var started := Time.get_ticks_msec()
	var ready := warm_up.wait(SHORT_MS)
	var took := Time.get_ticks_msec() - started
	assert_bool(ready).is_false()
	assert_int(warm_up.error).is_equal(ERR_TIMEOUT)
	assert_str(warm_up.error_text).is_equal("no offer in %d ms" % SHORT_MS)
	assert_int(took).is_greater_equal(SHORT_MS)
	warm_up.close()


func test_wait_returns_at_once_when_the_setup_already_failed() -> void:
	var warm_up := NeverReady.new()
	warm_up.error = ERR_CANT_CREATE
	warm_up.error_text = "create_data_channel gave null"
	var started := Time.get_ticks_msec()
	var ready := warm_up.wait(WebRtcWarmUp.READY_WITHIN_MS)
	assert_bool(ready).is_false()
	assert_int(Time.get_ticks_msec() - started).is_less(WebRtcWarmUp.READY_WITHIN_MS)
	assert_int(warm_up.error).is_equal(ERR_CANT_CREATE)
	assert_str(warm_up.error_text).is_equal("create_data_channel gave null")
	warm_up.close()
