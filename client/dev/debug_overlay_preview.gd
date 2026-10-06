extends Node
## A preview of the debug overlay (F3) for `tools\run.cmd shot` (the M4 ADR's §6): the host's view,
## with made-up numbers over a grey backdrop. Dev only: nothing here reaches the game.
## `in_round` shows it during a Round: the relay's counters give way to their note, and the voice
## lines (the own voice, two speakers) come into view (debug_overlay_voice_preview.tscn).
## The own connection's line: the host's player's is in this process; `joiner` shows a joiner's
## view instead, its direct connection and round trip, and no host counters
## (debug_overlay_joiner_preview.tscn, #431).

@export var in_round := false
@export var joiner := false


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.35, 0.38, 0.42)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	var overlay := DebugOverlay.new()
	overlay.theme = GameUi.THEME
	overlay.visible = true
	layer.add_child(overlay)
	var counters: Dictionary[StringName, int] = {
		&"over_budget": 0, &"bad_payloads": 0, &"malformed_disconnects": 0
	}
	if joiner:
		counters.clear()
		overlay.show_connection(NetTransport.Route.DIRECT, 48)
	else:
		overlay.show_connection(NetTransport.Route.LOCAL, -1)
	overlay.show_numbers(0, 1, 4821, 150.0, counters)
	if joiner:
		return
	# The relay's counters as the lobby shows them (M5-4); a round shows only the note.
	var relay: Dictionary[StringName, int] = {
		&"session_ms": 62753,
		&"voice_relayed": 15657,
		&"voice_sent": 109037,
		&"voice_dropped": 0,
		&"voice_over_budget": 0,
		&"voice_relay_usec": 6577467,
		&"voice_send_usec": 2036101,
		&"voice_up_bytes": 6459599,
		&"voice_up_datagrams": 95195,
		&"snapshots_sent": 9970,
		&"snapshot_up_bytes": 2900578,
		&"snapshot_up_datagrams": 8816,
		&"other_up_bytes": 26865,
		&"other_up_datagrams": 1709,
	}
	var phase := PhaseSpec.new()
	phase.phase_class = RoundPhase if in_round else LobbyPhase
	overlay.show_relay(relay, phase)
	# The own voice and two voices played, by index of first arrival (M5-5, M5-6).
	overlay.show_own_voice(true, true, 0.21, 23000, 412)
	var first := VoiceSpeaker.Stats.new()
	first.index = 1
	first.queue_ms = 60
	first.prebuffer_ms = 40
	first.received = 1520
	first.late = 3
	first.lost = 2
	first.concealed = 2
	first.decode_us = 38
	var second := VoiceSpeaker.Stats.new()
	second.index = 2
	second.queue_ms = 80
	second.prebuffer_ms = 60
	second.received = 640
	second.underruns = 1
	second.decode_us = 41
	overlay.show_voice([first, second])
