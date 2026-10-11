class_name OverlayFeed
extends RefCounted
## What Game's debug overlay (F3, debug builds only, invariant 8) shows each frame, out of game.gd
## to keep it under lint's 1000 lines (#254).


## The overlay's numbers, while it shows: the own client's, its own connection (only its own
## ClientSession's, the M6 design §3 item 4), and on the host the session's counters and, outside a
## Round, the voice relay's (DebugOverlay.shows_relay). The own session measures its round trip
## only while the overlay shows (WebRTC pings for it). `host` is null on a client.
static func refresh(
	overlay: DebugOverlay,
	client: ClientSession,
	host: HostNode,
	avatars: AvatarViews,
	sender: VoiceSender,
	voices: VoiceViews,
) -> void:
	var shown := overlay != null and overlay.visible
	if client != null:
		client.set_measuring_round_trip(shown)
	if not shown:
		return
	var counters: Dictionary[StringName, int] = {}
	refresh_voice(overlay, sender, voices)
	if client == null:
		overlay.show_numbers(-1, -1, -1, 0.0, counters)
		overlay.show_relay(counters, null)
		overlay.show_connection(NetTransport.Route.NONE, -1)
		return
	overlay.show_connection(client.route(), client.round_trip_ms())
	var relay: Dictionary[StringName, int] = {}
	if host != null:
		counters = host.counters()
		relay = host.relay_counters()
	overlay.show_numbers(
		client.corrections, client.placements, avatars.host_tick(), avatars.delay_ms(), counters
	)
	overlay.show_relay(relay, client.model.phase_spec())


## The overlay's voice lines: the own voice, then one per speaker played, by index of first
## arrival (E47).
static func refresh_voice(overlay: DebugOverlay, sender: VoiceSender, voices: VoiceViews) -> void:
	overlay.show_own_voice(
		sender.is_open(),
		sender.gate.is_open(),
		sender.peak,
		sender.frame_age_usec,
		sender.encode_usec
	)
	overlay.show_voice(voices.stats())
