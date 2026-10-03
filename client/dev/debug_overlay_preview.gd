extends Node
## A preview of the debug overlay (F3) for `tools\run.cmd shot` (the M4 ADR's §6): the host's view,
## with made-up numbers over a grey backdrop. Dev only: nothing here reaches the game.


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
	overlay.show_numbers(0, 1, 4821, 150.0, counters)
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
	var lobby := PhaseSpec.new()
	lobby.phase_class = LobbyPhase
	overlay.show_relay(relay, lobby)
