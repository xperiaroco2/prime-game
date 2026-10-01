extends GdUnitTestSuite
## The debug overlay's text (the M4 ADR's §2): the own client's corrections, the estimated host
## tick and the delay, and the host's counters sorted by name; nothing but a note without a session.


func test_a_client_shows_its_own_numbers() -> void:
	var counters: Dictionary[StringName, int] = {}
	var text := DebugOverlay.text(2, 1234, 149.6, counters)
	assert_str(text).contains("corrections: 2")
	assert_str(text).contains("host tick (estimated): 1234")
	assert_str(text).contains("interpolation delay: 150 ms")
	assert_str(text).not_contains("host:")


func test_the_host_adds_its_session_counters_by_name() -> void:
	var counters: Dictionary[StringName, int] = {
		&"voice_dropped": 3, &"over_budget": 0, &"malformed_disconnects": 0, &"bad_payloads": 1
	}
	var lines := DebugOverlay.text(0, 10, 100.0, counters).split("\n")
	var host := lines.find("host:")
	assert_int(host).is_greater(0)
	var listed := Array(lines.slice(host + 1))
	assert_array(listed).is_equal(
		[
			"  bad_payloads: 1",
			"  malformed_disconnects: 0",
			"  over_budget: 0",
			"  voice_dropped: 3"
		]
	)


func test_without_a_session_it_says_so() -> void:
	var counters: Dictionary[StringName, int] = {}
	assert_str(DebugOverlay.text(-1, -1, 0.0, counters)).is_equal("debug (F3): no session")


func test_it_starts_hidden_and_shows_what_it_is_given() -> void:
	var overlay: DebugOverlay = auto_free(DebugOverlay.new())
	assert_bool(overlay.visible).is_false()
	var counters: Dictionary[StringName, int] = {}
	overlay.show_numbers(5, 7, 100.0, counters)
	assert_str(overlay.label.text).contains("corrections: 5")
