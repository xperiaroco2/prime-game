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
	overlay.visible = true
	layer.add_child(overlay)
	var counters: Dictionary[StringName, int] = {
		&"over_budget": 0, &"bad_payloads": 0, &"malformed_disconnects": 0, &"voice_dropped": 2
	}
	overlay.show_numbers(0, 4821, 150.0, counters)
