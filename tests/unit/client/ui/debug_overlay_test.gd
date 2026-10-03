extends GdUnitTestSuite
## The debug overlay's text (the M4 ADR's §2): the own client's corrections and placements,
## the estimated host tick and the delay, and the host's counters sorted by name; nothing but a
## note without a session. Apart, the host's voice relay counters, only in a Lobby, a Countdown
## or an End (the M5 ADR §3 item 11).

const BASE_MODE := "res://content/modes/base_mode.tres"


func test_a_client_shows_its_own_numbers() -> void:
	var counters: Dictionary[StringName, int] = {}
	var text := DebugOverlay.text(2, 3, 1234, 149.6, counters)
	assert_str(text).contains("corrections: 2")
	assert_str(text).contains("placements: 3")
	assert_str(text).contains("host tick (estimated): 1234")
	assert_str(text).contains("interpolation delay: 150 ms")
	assert_str(text).not_contains("host:")


func test_the_host_adds_its_session_counters_by_name() -> void:
	var counters: Dictionary[StringName, int] = {
		&"over_budget": 3, &"malformed_disconnects": 0, &"bad_payloads": 1
	}
	var lines := DebugOverlay.text(0, 1, 10, 100.0, counters).split("\n")
	var host := lines.find("host:")
	assert_int(host).is_greater(0)
	var listed := Array(lines.slice(host + 1))
	assert_array(listed).is_equal(
		["  bad_payloads: 1", "  malformed_disconnects: 0", "  over_budget: 3"]
	)


func test_without_a_session_it_says_so() -> void:
	var counters: Dictionary[StringName, int] = {}
	assert_str(DebugOverlay.text(-1, -1, -1, 0.0, counters)).is_equal("debug (F3): no session")


func test_it_starts_hidden_and_shows_what_it_is_given() -> void:
	var overlay: DebugOverlay = auto_free(DebugOverlay.new())
	assert_bool(overlay.visible).is_false()
	var counters: Dictionary[StringName, int] = {}
	overlay.show_numbers(5, 1, 7, 100.0, counters)
	assert_str(overlay.label.text).contains("corrections: 5")


func test_the_relay_counters_show_by_name_or_only_the_note_and_nothing_on_a_client() -> void:
	var counters: Dictionary[StringName, int] = {&"voice_sent": 40, &"voice_relayed": 10}
	assert_str(DebugOverlay.relay_text(counters, true)).is_equal(
		"host voice (session totals):\n  voice_relayed: 10\n  voice_sent: 40"
	)
	assert_str(DebugOverlay.relay_text(counters, false)).is_equal(DebugOverlay.RELAY_HIDDEN)
	var none: Dictionary[StringName, int] = {}
	assert_str(DebugOverlay.relay_text(none, true)).is_empty()


func test_the_relay_counters_show_in_the_lobby_countdown_and_end_only() -> void:
	var mode := load(BASE_MODE) as GameMode
	var shown: Array[StringName] = []
	for phase: PhaseSpec in mode.phases:
		if DebugOverlay.shows_relay(phase):
			shown.append(phase.id)
	assert_array(shown).contains_exactly([&"lobby", &"countdown", &"end"])
	assert_bool(DebugOverlay.shows_relay(mode.find_phase(&"round"))).is_false()
	assert_bool(DebugOverlay.shows_relay(null)).is_false()


func test_the_relay_label_shows_what_the_phase_allows() -> void:
	var mode := load(BASE_MODE) as GameMode
	var overlay: DebugOverlay = auto_free(DebugOverlay.new())
	var counters: Dictionary[StringName, int] = {&"voice_sent": 7}
	overlay.show_relay(counters, mode.find_phase(&"lobby"))
	assert_bool(overlay.relay_label.visible).is_true()
	assert_str(overlay.relay_label.text).contains("voice_sent: 7")
	overlay.show_relay(counters, mode.find_phase(&"round"))
	assert_str(overlay.relay_label.text).is_equal(DebugOverlay.RELAY_HIDDEN)
	assert_str(overlay.relay_label.text).not_contains("7")
	var none: Dictionary[StringName, int] = {}
	overlay.show_relay(none, mode.find_phase(&"lobby"))
	assert_bool(overlay.relay_label.visible).is_false()


func test_the_voice_lines_number_each_speaker_and_name_no_one() -> void:
	assert_str(DebugOverlay.voice_text([])).is_empty()
	var first := VoiceSpeaker.Stats.new()
	first.index = 1
	first.queue_ms = 60
	first.prebuffer_ms = 40
	first.received = 120
	first.late = 2
	first.lost = 1
	first.concealed = 3
	first.underruns = 4
	first.decode_us = 35
	var second := VoiceSpeaker.Stats.new()
	second.index = 2
	var text := DebugOverlay.voice_text([first, second])
	assert_str(text).contains("#1 queue 60 ms, prebuffer 40 ms, frames 120, late 2, lost 1")
	assert_str(text).contains("concealed 3").contains("underruns 4").contains("decode 35 us")
	assert_str(text).contains("#2 queue 0 ms")
	assert_str(text).not_contains("peer")
	var overlay: DebugOverlay = auto_free(DebugOverlay.new())
	overlay.show_voice([first])
	assert_bool(overlay.voice_label.visible).is_true()
	overlay.show_voice([])
	assert_bool(overlay.voice_label.visible).is_false()
