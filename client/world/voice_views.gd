class_name VoiceViews
extends Node
## Plays the voices this client hears (the M5 ADR §1.5 and §3; ARCHITECTURE §6): one VoiceSpeaker
## per remote speaker at the mouth of its RemotePlayerBody (freed with the body), fed only the
## frames of ClientSession.voice_received, from the own ClientModel, the interpolated poses, the
## ears and the client's own copy of the mode (invariant 2: the host's own client too). The host
## already routed each frame by core/'s rule; this view only narrows what it plays, never widens
## it:
## - nothing for a speaker without a RemotePlayerBody, nor for one whose life fold is not living,
##   who left, or the own peer; nothing while the own life fold is dead (every speaker is flushed at
##   the own Died); nothing in a phase whose voice rule hears nobody (VoiceRule.radius_of 0: every
##   speaker is flushed on entering it); nothing of a speaker past `max_distance` from the ears;
## - a speaker whose life fold turns downed or dead is faded (VoiceJitter.FADE_USEC, 50 ms) and
##   flushed, one who leaves is flushed and its player freed, and one past `max_distance` from the
##   ears is faded and flushed;
## - late frames: voice travels on the unreliable VOICE lane and events on a reliable one, which
##   ENet does not order against each other, so at each flush this view records the newest host
##   tick it has seen (snapshots and frames) and drops that speaker's frames stamped at or below it
##   (E11's tick); the checks above apply to every frame, not only at the event.
## `max_distance` is the current phase's VoiceRule.radius_of() from the client's own mode (E41),
## set on every speaker at each phase change; no radius is copied into client tuning.
## Arrivals are stamped with `clock` when ClientSession delivers them (once a poll), and each
## speaker steps once a frame. Without the codec (the addon absent) nothing is played.

## After LifeView (5) placed the ears in the physics step, before SightHider (10).
const PHYSICS_PRIORITY := 8

var model: ClientModel
## The client's own copy of the game mode: each phase's voice rule.
var mode: GameMode
var avatars: AvatarViews
## The codec that decodes and plays; the base codec, never available, until the game sets one.
var codec := VoiceCodec.new()
## The ears' position: Called with no arguments, returns a Vector3, or null for no listener (then
## nothing plays). The viewport's current AudioListener3D unless a test sets one.
var ears := Callable()
## The clock in microseconds: Time.get_ticks_usec() unless a test sets one.
var clock := Callable()
## Frames delivered, frames handed to a speaker, and frames dropped by the rules above (debug).
var received := 0
var played := 0
var dropped := 0

var _speakers: Dictionary[int, VoiceSpeaker] = {}
## Peer -> the newest host tick seen at its latest flush: its frames stamped at or below it are
## dropped.
var _flushed_at: Dictionary[int, int] = {}
## Peer -> its index of first arrival, from 1 (the F3 lines name no peer, E47).
var _index: Dictionary[int, int] = {}
var _newest_tick := -1
var _cutoff_m := 0.0


func _init() -> void:
	name = "Voices"
	process_physics_priority = PHYSICS_PRIORITY


## Follows `client`'s voice and events with `game_mode`'s phases; `views` draws the speakers'
## bodies; `voice_codec` decodes. Until reset().
func setup(
	client: ClientSession, game_mode: GameMode, views: AvatarViews, voice_codec: VoiceCodec
) -> void:
	model = client.model
	mode = game_mode
	avatars = views
	codec = voice_codec
	client.voice_received.connect(on_voice)
	client.event_received.connect(on_event)
	client.snapshot_received.connect(on_snapshot)
	_cutoff_m = _phase_radius()


## Forgets the session (it ended): every speaker flushed and freed, every record dropped.
func reset() -> void:
	for peer: int in _speakers.keys():
		_free_speaker(peer)
	_flushed_at.clear()
	_index.clear()
	_newest_tick = -1
	model = null
	_cutoff_m = 0.0


## The cutoff now: the current phase's hearing radius from the own mode, 0 for none.
func cutoff() -> float:
	return _cutoff_m


## The speaker of `peer`, or null.
func speaker_of(peer: int) -> VoiceSpeaker:
	var speaker: VoiceSpeaker = _speakers.get(peer)
	return speaker if is_instance_valid(speaker) else null


## The newest host tick recorded at `peer`'s latest flush, or -1 before any.
func flushed_at(peer: int) -> int:
	return _flushed_at.get(peer, -1)


## One VoiceDown (ClientSession.voice_received): handed to its speaker if every rule allows it.
func on_voice(speaker: int, seq: int, tick: int, opus: PackedByteArray) -> void:
	received += 1
	_see_tick(tick)
	if not hears(speaker, tick):
		dropped += 1
		return
	var player := _speaker_for(speaker)
	if player == null:
		dropped += 1
		return
	if not _index.has(speaker):
		_index[speaker] = _index.size() + 1
	player.push(seq, tick, opus, now_usec())
	played += 1


## Whether a frame of `speaker` stamped at host tick `tick` may play now, by every rule but the
## body and the distance: the codec, the own life, the phase's radius, the speaker's life and
## presence, and the tick of its latest flush.
func hears(speaker: int, tick: int) -> bool:
	if model == null or not codec.available() or speaker == model.own_peer:
		return false
	if _own_dead():
		return false
	if _cutoff_m <= 0.0:
		return false
	if not model.roster.has(speaker) or model.life_of(speaker) != ClientModel.Life.ALIVE:
		return false
	return tick > flushed_at(speaker)


## The session's events (ClientSession.event_received, after the model folded each).
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if model == null:
		return
	match event_name:
		&"PhaseChanged":
			_cutoff_m = _phase_radius()
			if _cutoff_m <= 0.0:
				flush_all()
			for peer: int in _speakers:
				if is_instance_valid(_speakers[peer]):
					_speakers[peer].set_cutoff(_cutoff_m)
		&"Died":
			if fields["peer"] as int == model.own_peer:
				flush_all()
			else:
				fade(fields["peer"] as int)
		&"KnockedDown":
			# The own player downed still hears the living, from where it lies.
			if fields["peer"] as int != model.own_peer:
				fade(fields["peer"] as int)
		&"PlayerLeft":
			var peer: int = fields["peer"]
			_record_flush(peer)
			_free_speaker(peer)


## Every snapshot's tick counts as seen (ClientSession.snapshot_received).
func on_snapshot(tick: int, _avatars: Dictionary) -> void:
	_see_tick(tick)


## Fades `peer`'s voice out and flushes it (VoiceSpeaker.fade_out()), recording the tick.
func fade(peer: int) -> void:
	_record_flush(peer)
	var speaker := speaker_of(peer)
	if speaker != null:
		speaker.fade_out(now_usec())


## Flushes every speaker at once, recording the tick for each.
func flush_all() -> void:
	for peer: int in _speakers.keys():
		_record_flush(peer)
		var speaker := speaker_of(peer)
		if speaker != null:
			speaker.flush_now()


## Each speaker's debug numbers, by index of first arrival (the F3 overlay; no peer id).
func stats() -> Array[VoiceSpeaker.Stats]:
	var out: Array[VoiceSpeaker.Stats] = []
	for peer: int in _speakers:
		var speaker := speaker_of(peer)
		if speaker != null and _index.has(peer):
			out.append(speaker.stats(_index[peer]))
	out.sort_custom(
		func(a: VoiceSpeaker.Stats, b: VoiceSpeaker.Stats) -> bool: return a.index < b.index
	)
	return out


func now_usec() -> int:
	return clock.call() as int if clock.is_valid() else Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := now_usec()
	for peer: int in _speakers.keys():
		var speaker := speaker_of(peer)
		if speaker == null:
			# Freed with its body (no avatar any more): a new body gets a new speaker.
			_speakers.erase(peer)
			continue
		speaker.step(now)


## A speaker past the cutoff from the ears is faded and flushed.
func _physics_process(_delta: float) -> void:
	if model == null:
		return
	var heard_from: Variant = _ears_position()
	for peer: int in _speakers.keys():
		var speaker := speaker_of(peer)
		if speaker == null or speaker.fading() or not speaker.is_active():
			continue
		if not heard_from is Vector3 or not _within(speaker, heard_from as Vector3):
			fade(peer)


## The speaker of `peer` on its body, made at its first frame; null without a body, or when the
## ears are farther from its mouth than the cutoff.
func _speaker_for(peer: int) -> VoiceSpeaker:
	var speaker := speaker_of(peer)
	if speaker == null:
		var body := avatars.body_of(peer) if avatars != null else null
		if body == null or not body.is_inside_tree():
			return null
		speaker = VoiceSpeaker.new(codec)
		speaker.set_cutoff(_cutoff_m)
		body.mouth_point().add_child(speaker)
		_speakers[peer] = speaker
	var heard_from: Variant = _ears_position()
	if not heard_from is Vector3 or not _within(speaker, heard_from as Vector3):
		return null
	return speaker


func _within(speaker: VoiceSpeaker, heard_from: Vector3) -> bool:
	return speaker.global_position.distance_to(heard_from) <= _cutoff_m


func _record_flush(peer: int) -> void:
	if model != null:
		_see_tick(model.snapshot_tick)
	_flushed_at[peer] = _newest_tick


func _see_tick(tick: int) -> void:
	_newest_tick = maxi(_newest_tick, tick)


func _free_speaker(peer: int) -> void:
	var speaker := speaker_of(peer)
	if speaker != null:
		speaker.flush_now()
		speaker.queue_free()
	_speakers.erase(peer)


func _own_dead() -> bool:
	var own := model.life_of(model.own_peer)
	return own == ClientModel.Life.DEAD or own == ClientModel.Life.LEFT


func _phase_radius() -> float:
	if model == null or mode == null:
		return 0.0
	var spec := mode.find_phase(model.phase)
	return VoiceRule.radius_of(spec.voice_rule if spec != null else null)


func _ears_position() -> Variant:
	if ears.is_valid():
		return ears.call()
	if not is_inside_tree():
		return null
	var listener := get_viewport().get_audio_listener_3d()
	return listener.global_position if listener != null else null
