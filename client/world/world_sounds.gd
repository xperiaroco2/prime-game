class_name WorldSounds
extends Node3D
## Plays M4's placeholder world sounds (ARCHITECTURE §4.7; the M4 ADR's D9, E33 (a); M4-8): for
## each event SoundChooser picks within the hearing range of the ears (E40's amendment of E33:
## the current AudioListener3D, LifeView's Ears), a one-shot AudioStreamPlayer3D at its place on
## the Effects bus (D15), with `max_distance` the same range, freed when it ends.
##
## The sounds are short blips built in code (no asset, nothing downloaded): placeholders, until
## CC0 sounds are picked with their docs/credits/ entries (D9, a human step).

## Samples per second of the generated blips.
const MIX_RATE := 22050

var model: ClientModel
## The remote players' interpolated poses: where another player swings.
var avatars: AvatarViews
## The local player: where the own swing is.
var player: PlayerController
## The listener's position: the viewport's current AudioListener3D (the ears), else its current
## camera, unless a test sets one. Called with no arguments, returns a Vector3, or null for no
## listener (no sound).
var listener := Callable()

var _streams: Dictionary[StringName, AudioStreamWAV] = {}
var _played := 0


func _init() -> void:
	for id: StringName in [SoundChooser.SWING, SoundChooser.PICK_UP, SoundChooser.PUT_DOWN]:
		_streams[id] = blip(id)


## The session's events (connected by the game to ClientSession.event_received).
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if model == null:
		return
	var heard_from: Variant = null
	if listener.is_valid():
		heard_from = listener.call()
	else:
		heard_from = _ears_position()
	if not heard_from is Vector3:
		return
	var sound := SoundChooser.choose(event_name, fields, model, position_of, heard_from as Vector3)
	if sound == null:
		return
	var sound_player := AudioStreamPlayer3D.new()
	sound_player.name = "Sound%d" % _played
	sound_player.stream = _streams[sound.id]
	sound_player.max_distance = SoundChooser.HEARING_RANGE_M
	sound_player.bus = AudioBuses.EFFECTS
	sound_player.position = sound.position
	sound_player.finished.connect(sound_player.queue_free)
	add_child(sound_player)
	sound_player.play()
	_played += 1


## How many sounds were started (tests).
func played() -> int:
	return _played


## Where `peer` is as this client draws it: the local player, or another player's body; null when
## the client draws no such player.
func position_of(peer: int) -> Variant:
	if model != null and peer == model.own_peer and player != null and player.is_inside_tree():
		return player.global_position
	var body := avatars.body_of(peer) if avatars != null else null
	if body == null or not body.is_inside_tree():
		return null
	return body.global_position


## The placeholder sound `id`: a short 16-bit mono blip, a falling noise burst for a swing, a
## rising tone for a pick-up and a low thud for a put-down.
static func blip(id: StringName) -> AudioStreamWAV:
	var seconds := 0.15
	var data := PackedByteArray()
	var count := int(MIX_RATE * seconds)
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i: int in count:
		var t := float(i) / MIX_RATE
		var fade := 1.0 - float(i) / count
		var value := 0.0
		match id:
			SoundChooser.SWING:
				value = rng.randf_range(-1.0, 1.0) * fade * fade
			SoundChooser.PICK_UP:
				value = sin(TAU * (500.0 + 2000.0 * t) * t) * fade
			_:
				value = sin(TAU * 90.0 * t) * fade * fade
		data.encode_s16(i * 2, int(value * 0.5 * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	return stream


## The current AudioListener3D's position (the ears), else the current camera's, else null.
func _ears_position() -> Variant:
	if not is_inside_tree():
		return null
	var ears := get_viewport().get_audio_listener_3d()
	if ears != null:
		return ears.global_position
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	return camera.global_position
