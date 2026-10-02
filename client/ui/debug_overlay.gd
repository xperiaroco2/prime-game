class_name DebugOverlay
extends PanelContainer
## The debug overlay (the M4 ADR's §2; F3, debug builds only, invariant 8): the own client's count
## of Corrections of refused claims and, apart, of placements (a placement or a death sends one
## too), the estimated host tick and the interpolation delay, and on the host the session's
## counters (budgets, malformed messages, voice). The playtests read it, above all for #76's
## tuning: honest play gets no correction, only placements. The game creates it in debug builds
## only and feeds it while it shows; it reads nothing itself.

var label := Label.new()


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(8, 8)
	label.theme_type_variation = &"DebugText"
	var margin := MarginContainer.new()
	margin.theme_type_variation = &"DebugMargin"
	margin.add_child(label)
	add_child(margin)


## Shows the numbers; `corrections` -1 when no session runs, `counters` empty on a client.
func show_numbers(
	corrections: int,
	placements: int,
	host_tick: int,
	delay_ms: float,
	counters: Dictionary[StringName, int]
) -> void:
	label.text = text(corrections, placements, host_tick, delay_ms, counters)


## The overlay's lines (pure, for the tests).
static func text(
	corrections: int,
	placements: int,
	host_tick: int,
	delay_ms: float,
	counters: Dictionary[StringName, int]
) -> String:
	if corrections < 0:
		return "debug (F3): no session"
	var lines := PackedStringArray(
		[
			"debug (F3)",
			"corrections: %d" % corrections,
			"placements: %d" % placements,
			"host tick (estimated): %d" % host_tick,
			"interpolation delay: %d ms" % roundi(delay_ms),
		]
	)
	if not counters.is_empty():
		lines.append("host:")
		var names := counters.keys()
		# StringNames do not sort by their text on their own.
		names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		for key: StringName in names:
			lines.append("  %s: %d" % [key, counters[key]])
	return "\n".join(lines)
