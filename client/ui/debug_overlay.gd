class_name DebugOverlay
extends PanelContainer
## The debug overlay (the M4 ADR's §2; F3, debug builds only, invariant 8): the own client's count
## of Corrections of refused claims and, apart, of placements (a placement or a death sends one
## too), the estimated host tick and the interpolation delay, and on the host the session's
## counters (budgets, malformed messages). The playtests read it, above all for #76's tuning:
## honest play gets no correction, only placements. The game creates it in debug builds only and
## feeds it while it shows; it reads nothing itself.
##
## On the host, apart, the voice relay's counters (relayed, sent, dropped, over budget, relay µs,
## the voice and snapshot upload; HostNode.relay_counters, M5-4) as totals since the session
## started, only in the Lobby, the Countdown and End (shows_relay): live during a Round they would
## tell the host's player how many hear them (the M5 ADR §3 item 11).
##
## Below them, one line per voice this client plays (M5-5, E47; show_voice()): by an index in
## order of first arrival, never a peer id or a name (the M5 ADR §3 item 10).

const RELAY_HIDDEN := "host voice: shown in the lobby, the countdown and the end"

var label := Label.new()
## The host's voice relay counters, or the note that hides them; empty on a client.
var relay_label := Label.new()
## The per-speaker voice lines (show_voice()).
var voice_label := Label.new()


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(8, 8)
	label.theme_type_variation = &"DebugText"
	relay_label.theme_type_variation = &"DebugText"
	relay_label.visible = false
	var margin := MarginContainer.new()
	margin.theme_type_variation = &"DebugMargin"
	var lines := VBoxContainer.new()
	lines.add_child(label)
	lines.add_child(relay_label)
	voice_label.theme_type_variation = &"DebugText"
	voice_label.visible = false
	lines.add_child(voice_label)
	margin.add_child(lines)
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


## Shows the host's voice relay counters for the client's own copy of the current phase (`phase`
## null before a Welcome); `counters` empty on a client, which shows nothing.
func show_relay(counters: Dictionary[StringName, int], phase: PhaseSpec) -> void:
	relay_label.text = relay_text(counters, shows_relay(phase))
	relay_label.visible = not relay_label.text.is_empty()


## Whether the relay's counters may show during `phase`: only while its class is LobbyPhase,
## CountdownPhase or EndPhase, never with no phase known. Every other phase class hides them, one
## added later included.
static func shows_relay(phase: PhaseSpec) -> bool:
	if phase == null:
		return false
	var shown_in: Array[Script] = [LobbyPhase, CountdownPhase, EndPhase]
	return shown_in.has(phase.phase_class)


## The relay's lines (pure, for the tests): by name when `shown`, else only the note; empty with
## no counters.
static func relay_text(counters: Dictionary[StringName, int], shown: bool) -> String:
	if counters.is_empty():
		return ""
	if not shown:
		return RELAY_HIDDEN
	var lines := PackedStringArray(["host voice (session totals):"])
	var names := counters.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for key: StringName in names:
		lines.append("  %s: %d" % [key, counters[key]])
	return "\n".join(lines)


## Shows one line per speaker played, or nothing when none is.
func show_voice(speakers: Array[VoiceSpeaker.Stats]) -> void:
	voice_label.text = voice_text(speakers)
	voice_label.visible = not voice_label.text.is_empty()


## The per-speaker voice lines (pure, for the tests): each by its index of first arrival, with its
## queue, prebuffer, frames received, late, lost, concealed (FEC or concealment), stale, underruns,
## overflow and decode time; empty for no speaker.
static func voice_text(speakers: Array[VoiceSpeaker.Stats]) -> String:
	if speakers.is_empty():
		return ""
	var lines := PackedStringArray(["voice (by first arrival):"])
	for s: VoiceSpeaker.Stats in speakers:
		lines.append(
			(
				"  #%d queue %d ms, prebuffer %d ms, frames %d, late %d, lost %d, concealed %d,"
				% [s.index, s.queue_ms, s.prebuffer_ms, s.received, s.late, s.lost, s.concealed]
			)
		)
		lines.append(
			(
				"     stale %d, underruns %d, overflow %d, decode %d us"
				% [s.stale, s.underruns, s.overflow, s.decode_us]
			)
		)
	return "\n".join(lines)
