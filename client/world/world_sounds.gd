class_name WorldSounds
extends Node3D
## Plays the world sounds (ARCHITECTURE §4.7, §4.7.43; the M4 ADR's D9, E33 (a); M4-8; #525): for
## each event SoundChooser picks within the hearing range of the ears (E40's amendment of E33:
## the current AudioListener3D, LifeView's Ears), a one-shot AudioStreamPlayer3D at its place on
## the Effects bus (D15), with `max_distance` the same range, freed when it ends.
## As it starts, one ray from the ears to the sound's aim (SoundChooser's SWING_AIM_M, ITEM_AIM_M
## or THROW_AIM_M above it) against the world layer of the client's own level (the M5 ADR §1.6,
## E42 (a), D13 (a); M5-7): behind the level it plays muffled (Muffle: 8 dB quieter, on the
## muffled Effects bus's low-pass), and stays so to its end.
##
## Footsteps (#525), each physics frame: of the local player while it is living,
## from how far it moved (is_on_floor() flickers on stairs: only FootstepSurface's ray decides the
## floor); of every other player this client draws while the model knows it living
## (not downed, dead or gone), from how far its interpolated pose moved (never a claimed
## velocity). FootstepCadence says when a step falls; SoundChooser.step cuts it beyond the hearing
## range before any ray; FootstepSurface's ray down finds the floor's surface, and no floor (a
## jump) plays none. Another player's step casts the muffle ray to SoundChooser.STEP_AIM_M above
## its feet; the own steps cast none (nothing stands between the ears and the own feet).
## Anywhere (the crouch plays everywhere, #991), a step at or below the mode's crouch_speed_mps is
## FootstepCadence.QUIET_STEP_DB quieter and heard within its QUIET_STEP_RANGE_M, easing to a walk's
## step at its crouch_fast_speed_mps (#792, #991, the crouch ADR's KD1 (b)): read from the step's
## speed, never the crouch flag. A sneaking player's step plays nothing (#989, #990): the sneak flag
## of the drawn pose (the own controller's, a body's relayed one) AND a step speed at or below
## crouch_speed_mps plus FootstepCadence.SNEAK_SPEED_MARGIN_MPS (FootstepCadence.silent_of), so a
## peer that claims the sneak while it walks faster is heard.
## The streams are SfxSet's: Kenney's CC0 files and the project's own task sounds, each id a
## randomizer. A throw's launch (#645) has
## no file yet: it plays release/m7's generated placeholder (throw_blip()) until one is picked.
## The photo task's shutter and print (#785, PD15) play generated placeholders too
## (photo_blip()), cut and muffled like every event's sound, the shutter at a camera's lens
## (`lens_m` above its marker). So do the Generator's clicks (#801, G6): a switch thrown and the
## generator's button pressed (station_blip()); its hum while it charges is StationHums'
## (hum_blip()). So do Cooking's (#776, the cooking ADR's CD14 (a)): a burger plated's chime, a
## patty fried's ding (cooking_blip()); the grill's put is the put-down's file, its sizzle while a
## patty fries StationHums' (sizzle_blip()). Every task's success and error (#1341, §4.7.60) are
## SfxSet's files (TASK_SUCCESS, TASK_ERROR), in place of the placeholders that meant done or a
## miss (Cooking's served burger and buzz, its burnt hiss, the car repair's part fitted, the
## photo's hang).

## Samples per second of the generated throw blip.
const MIX_RATE := 22050
## The photo task's placeholder blips (#785, PD15) and the length of each in seconds:
## placeholders, "not a decision", until the engineer's CC0 files arrive with their credits.
const PHOTO_BLIP_SECONDS: Dictionary[StringName, float] = {
	SoundChooser.SHUTTER: 0.08,
	SoundChooser.PRINT: 0.6,
}
## The Generator's placeholder clicks (#801, G6) and the length of each in seconds: placeholders,
## "not a decision", until the engineer's files arrive.
const STATION_BLIP_SECONDS: Dictionary[StringName, float] = {
	SoundChooser.SWITCH_CLICK: 0.05,
	SoundChooser.BUTTON_CLICK: 0.1,
	# The car repair's (#811, RD14): the lift's crash coming down.
	SoundChooser.LIFT_CRASH: 0.5,
}
## The hum's placeholder loop (#801, G6): its length in seconds, a whole number of its waves so
## the loop has no seam. A placeholder, "not a decision".
const HUM_SECONDS := 0.5
## Cooking's placeholder blips (#776, CD14 (a)) and the length of each in seconds: placeholders,
## "not a decision", until the engineer's CC0 files arrive with their credits.
const COOKING_BLIP_SECONDS: Dictionary[StringName, float] = {
	SoundChooser.CHIME: 0.35,
	SoundChooser.DING: 0.5,
}
## The sizzle's placeholder loop (#776): its length in seconds. A placeholder, "not a decision".
const SIZZLE_SECONDS := 0.5

var model: ClientModel
## The remote players' interpolated poses: where another player swings and walks.
var avatars: AvatarViews
## The local player: where the own swing is, and the own steps.
var player: PlayerController
## The listener's position: the viewport's current AudioListener3D (the ears), else its current
## camera, unless a test sets one. Called with no arguments, returns a Vector3, or null for no
## listener (no sound).
var listener := Callable()
## The streams.
var sfx := SfxSet.new()
## How far above a photo camera's marker its lens is, where the shutter plays: the client's own
## copy of the mode's eye height (ItemWorld sets it).
var lens_m := 0.0
## The client's own copy of the mode: which kinds are Cooking's fried and burnt patties (ItemWorld
## sets it).
var mode: GameMode

var _played := 0
var _rays := 0
var _muffled := 0
## The lift crashes chosen in this batch of events, played at the next physics frame (#811). The
## host's phase end stops a hold, whose LiftChanged comes down, before its PhaseChanged (Match:
## Channels.stop_all, then _enter_phase), so a crash that a PhaseChanged follows in the same batch
## is the phase end's, which drops no car and kills nobody (RE4, RD16 (c)): at the next physics
## frame the model has left the round, and the crash is dropped.
var _held_crashes: Array[SoundChooser.Sound] = []
var _steps := 0
## Where each player's feet were in the last physics frame, and its cadence; the own player's
## under 0 (no peer is 0).
var _feet: Dictionary[int, Vector3] = {}
var _cadences: Dictionary[int, FootstepCadence] = {}
## The throw's placeholder (throw_blip()), made once.
var _throw_blip: AudioStreamWAV = null
## The photo sounds' placeholders (photo_blip()), each made once, by sound id.
var _photo_blips: Dictionary[StringName, AudioStreamWAV] = {}
## The Generator's clicks (station_blip()), each made once, by sound id.
var _station_blips: Dictionary[StringName, AudioStreamWAV] = {}
## Cooking's sounds (cooking_blip()), each made once, by sound id.
var _cooking_blips: Dictionary[StringName, AudioStreamWAV] = {}


## Loads every sound now, not at the first footstep or swing in a round (the resource cache then
## serves the UI click too).
func _ready() -> void:
	for id: StringName in SfxSet.ids():
		sfx.stream_for(id)


## The session's events (connected by the game to ClientSession.event_received).
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if model == null:
		return
	var heard_from: Variant = _heard_from()
	if not heard_from is Vector3:
		return
	var sound := SoundChooser.choose(
		event_name,
		fields,
		model,
		position_of,
		heard_from as Vector3,
		SoundChooser.HEARING_RANGE_M,
		lens_m,
		mode
	)
	if sound == null:
		return
	if sound.id == SoundChooser.LIFT_CRASH:
		_held_crashes.append(sound)
		return
	_start(sound, _stream_of(sound.id), heard_from as Vector3, true)


## Plays the lift crashes held from the last batch of events while the round still runs (#811);
## each physics frame calls it first.
func play_held() -> void:
	if _held_crashes.is_empty():
		return
	var held := _held_crashes
	_held_crashes = []
	var heard_from: Variant = _heard_from()
	if not SoundChooser.in_play(model) or not heard_from is Vector3:
		return
	for sound: SoundChooser.Sound in held:
		_start(sound, _stream_of(sound.id), heard_from as Vector3, true)


## How many sounds were started, steps included (tests).
func played() -> int:
	return _played


## How many muffle rays were cast: one per sound started, but the own steps (tests).
func rays() -> int:
	return _rays


## How many of the sounds started were muffled (tests).
func muffled() -> int:
	return _muffled


## How many footsteps were started (tests).
func steps() -> int:
	return _steps


## The placeholder sound of a throw's launch (#645): a short 16-bit mono burst of noise that swells
## then fades.
static func throw_blip() -> AudioStreamWAV:
	var seconds := 0.15
	var data := PackedByteArray()
	var count := int(MIX_RATE * seconds)
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i: int in count:
		var value := rng.randf_range(-1.0, 1.0) * sin(PI * float(i) / count) * 0.8
		data.encode_s16(i * 2, int(value * 0.5 * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	return stream


## The placeholder sound of the photo task's sound `id` (#785, PD15: blips built in code, as
## throw_blip(), until the engineer's files arrive): a 16-bit mono burst PHOTO_BLIP_SECONDS long.
## The shutter two quick clicks; the printer a buzz stepping a dozen times a second. Null for an
## id with no blip.
static func photo_blip(id: StringName) -> AudioStreamWAV:
	if not PHOTO_BLIP_SECONDS.has(id):
		return null
	var seconds: float = PHOTO_BLIP_SECONDS[id]
	var data := PackedByteArray()
	var count := int(MIX_RATE * seconds)
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i: int in count:
		var t := float(i) / MIX_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		var value := 0.0
		if id == SoundChooser.SHUTTER:
			value = noise * exp(-t / 0.004)
			if t >= 0.045:
				value += 0.7 * noise * exp(-(t - 0.045) / 0.004)
		else:
			var fade := minf(1.0, minf(t / 0.02, (seconds - t) / 0.05))
			var step := 0.6 + 0.4 * signf(sin(TAU * 12.0 * t))
			value = 0.5 * signf(sin(TAU * 180.0 * t)) * step * fade
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 0.5 * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	return stream


## The placeholder click of the Generator's sound `id` (#801, G6; built in code as photo_blip()
## until the engineer's files arrive): a switch's two sharp snaps, the button's low thunk, the
## lift's crash; a 16-bit mono burst STATION_BLIP_SECONDS long. Null for an id with no click.
static func station_blip(id: StringName) -> AudioStreamWAV:
	if not STATION_BLIP_SECONDS.has(id):
		return null
	var seconds: float = STATION_BLIP_SECONDS[id]
	var count := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i: int in count:
		var t := float(i) / MIX_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		var value := 0.0
		if id == SoundChooser.SWITCH_CLICK:
			value = noise * exp(-t / 0.002)
			if t >= 0.02:
				value += 0.6 * noise * exp(-(t - 0.02) / 0.002)
		elif id == SoundChooser.LIFT_CRASH:
			# A heavy thud and a metal rattle.
			value = sin(TAU * 55.0 * t) * exp(-t / 0.08) + 0.7 * noise * exp(-t / 0.12)
		else:
			value = sin(TAU * 90.0 * t) * exp(-t / 0.025) + 0.4 * noise * exp(-t / 0.004)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 0.5 * 32767.0))
	return _wav(data, false)


## The placeholder hum of a charging generator (#801, G6): a looping low buzz, 100 Hz with its
## second and third harmonics, HUM_SECONDS long (a whole number of 100 Hz waves: no seam).
static func hum_blip() -> AudioStreamWAV:
	var count := int(MIX_RATE * HUM_SECONDS)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i: int in count:
		var t := float(i) / MIX_RATE
		var value := (
			0.6 * sin(TAU * 100.0 * t)
			+ 0.3 * sin(TAU * 200.0 * t)
			+ 0.15 * signf(sin(TAU * 300.0 * t))
		)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 0.4 * 32767.0))
	return _wav(data, true)


## The placeholder of Cooking's sound `id` (#776, CD14 (a); built in code as station_blip() until
## the engineer's files arrive), a 16-bit mono burst COOKING_BLIP_SECONDS long: the chime's two
## bright tones, the ding's bell. Null for an id with no blip.
static func cooking_blip(id: StringName) -> AudioStreamWAV:
	if not COOKING_BLIP_SECONDS.has(id):
		return null
	var seconds: float = COOKING_BLIP_SECONDS[id]
	var count := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i: int in count:
		var t := float(i) / MIX_RATE
		var value := 0.0
		if id == SoundChooser.CHIME:
			value = (0.6 * sin(TAU * 880.0 * t) + 0.4 * sin(TAU * 1320.0 * t)) * exp(-t / 0.1)
		else:
			value = (0.8 * sin(TAU * 1500.0 * t) + 0.2 * sin(TAU * 3000.0 * t)) * exp(-t / 0.15)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 0.5 * 32767.0))
	return _wav(data, false)


## The placeholder sizzle of a patty on the grill (#776): a looping crackle of noise with sparse
## pops, SIZZLE_SECONDS long (noise has no wave to seam).
static func sizzle_blip() -> AudioStreamWAV:
	var count := int(MIX_RATE * SIZZLE_SECONDS)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var pop := 0.0
	for i: int in count:
		if rng.randf() < 0.002:
			pop = 1.0
		pop *= 0.995
		var value := rng.randf_range(-1.0, 1.0) * (0.25 + 0.75 * pop)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 0.4 * 32767.0))
	return _wav(data, true)


## The ears' position now (the test's listener, the AudioListener3D, else the camera), or null:
## StationHums' hearing range and muffle ray start there too.
func ears() -> Variant:
	return _heard_from()


## A 16-bit mono stream of `data` at MIX_RATE, looping over the whole of it if `loop`.
static func _wav(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = data.size() >> 1
	return stream


## Where `peer` is as this client draws it: the local player (knocked down, its avatar's point,
## KE5), or another player's body; null when the client draws no such player.
func position_of(peer: int) -> Variant:
	if model != null and peer == model.own_peer and player != null and player.is_inside_tree():
		var feet := player.global_position
		return avatars.point_of(peer, feet) if avatars != null else feet
	var body := avatars.body_of(peer) if avatars != null else null
	if body == null or not body.is_inside_tree():
		return null
	return body.global_position


func _physics_process(delta: float) -> void:
	play_held()
	var walking: Dictionary[int, Vector3] = {}
	if player != null and player.is_inside_tree() and player.is_living():
		walking[0] = player.global_position
	if model != null and avatars != null:
		for peer: int in model.avatars:
			var body := avatars.body_of(peer)
			if peer == model.own_peer or body == null or not body.is_inside_tree():
				continue
			if (
				model.is_alive(peer)
				and not (model.avatars[peer] as Dictionary).get("downed", false)
			):
				walking[peer] = body.global_position
	for gone: int in _feet.keys():
		if not walking.has(gone):
			_feet.erase(gone)
			_cadences.erase(gone)
	if walking.is_empty():
		return
	var heard_from: Variant = _heard_from()
	for peer: int in walking:
		var at := walking[peer]
		var moved := at - _feet[peer] if _feet.has(peer) else Vector3.ZERO
		_feet[peer] = at
		if not _cadences.has(peer):
			_cadences[peer] = FootstepCadence.new()
		var rules := _rules_of(peer)
		if rules == null:
			continue
		var due := _cadences[peer].advance(
			moved, delta, rules.walk_speed_mps, rules.sprint_speed_mps
		)
		if not due or not heard_from is Vector3:
			continue
		var step_speed := _cadences[peer].step_speed_mps
		if FootstepCadence.silent_of(_sneaking(peer), step_speed, rules.crouch_speed_mps):
			continue
		var quiet := FootstepCadence.quiet_of(
			step_speed, rules.crouch_speed_mps, rules.crouch_fast_speed_mps
		)
		_step(at, heard_from as Vector3, peer != 0, quiet)


## The movement numbers of `peer`'s steps (0: the own player): the client's own copy of the mode's.
func _rules_of(peer: int) -> PlayerRules:
	if peer == 0:
		return player.rules
	return avatars.rules


## Whether `peer`'s drawn pose sneaks (#990; 0: the own player's controller, else the sneak flag
## its body's interpolated pose carries).
func _sneaking(peer: int) -> bool:
	if peer == 0:
		return player.is_sneaking()
	var body := avatars.body_of(peer)
	return body != null and body.is_sneaking()


## A footstep of feet at `at` heard from `heard_from`, muffled by the level if `occlude`; `quiet`
## (FootstepCadence.quiet_of(), 0 a walk's step) lowers it toward QUIET_STEP_DB and narrows its
## hearing range toward QUIET_STEP_RANGE_M (the cut and max_distance alike).
func _step(at: Vector3, heard_from: Vector3, occlude: bool, quiet: float) -> void:
	var hearing_m := lerpf(SoundChooser.HEARING_RANGE_M, FootstepCadence.QUIET_STEP_RANGE_M, quiet)
	var sound := SoundChooser.step(at, heard_from, hearing_m)
	if sound == null:
		return
	var surface: Variant = FootstepSurface.DEFAULT
	if is_inside_tree():
		surface = FootstepSurface.under(get_world_3d().direct_space_state, at)
	if surface == null:
		return
	var stream: AudioStream = sfx.stream_for(SfxSet.footstep(surface as StringName))
	var quieter_db := lerpf(0.0, FootstepCadence.QUIET_STEP_DB, quiet)
	if _start(sound, stream, heard_from, occlude, hearing_m, quieter_db):
		_steps += 1


## The stream of an event's sound `id`: SfxSet's, else, for a throw's launch or a photo sound, which
## have no file yet, its placeholder (throw_blip(), photo_blip()); null for none.
func _stream_of(id: StringName) -> AudioStream:
	var stream: AudioStream = sfx.stream_for(id)
	if stream == null and id == SoundChooser.THROW:
		if _throw_blip == null:
			_throw_blip = throw_blip()
		stream = _throw_blip
	if stream == null and PHOTO_BLIP_SECONDS.has(id):
		if not _photo_blips.has(id):
			_photo_blips[id] = photo_blip(id)
		stream = _photo_blips[id]
	if stream == null and STATION_BLIP_SECONDS.has(id):
		if not _station_blips.has(id):
			_station_blips[id] = station_blip(id)
		stream = _station_blips[id]
	if stream == null and COOKING_BLIP_SECONDS.has(id):
		if not _cooking_blips.has(id):
			_cooking_blips[id] = cooking_blip(id)
		stream = _cooking_blips[id]
	return stream


## Starts `sound` with `stream`, muffled if `occlude` and the level is in the way, heard within
## `hearing_m` (max_distance) and `quieter_db` added to its volume; false (and nothing started)
## with no stream.
func _start(
	sound: SoundChooser.Sound,
	stream: AudioStream,
	heard_from: Vector3,
	occlude: bool,
	hearing_m := SoundChooser.HEARING_RANGE_M,
	quieter_db := 0.0,
) -> bool:
	if stream == null:
		return false
	var sound_player := AudioStreamPlayer3D.new()
	sound_player.name = "Sound%d" % _played
	sound_player.stream = stream
	sound_player.max_distance = hearing_m
	var muffle := Muffle.new()
	muffle.follow(occlude and _blocked(heard_from, sound.aim), 0.0)
	sound_player.volume_db = muffle.volume_db() + quieter_db
	sound_player.bus = muffle.bus_for(AudioBuses.EFFECTS)
	sound_player.position = sound.position
	sound_player.finished.connect(sound_player.queue_free)
	add_child(sound_player)
	sound_player.play()
	_played += 1
	return true


## The ears' position: the test's listener, else _ears_position(); null for none.
func _heard_from() -> Variant:
	if listener.is_valid():
		return listener.call()
	return _ears_position()


## The one ray from the ears `from` to the sound's aim `to`; outside the tree nothing is in the way.
func _blocked(from: Vector3, to: Vector3) -> bool:
	if not is_inside_tree():
		return false
	_rays += 1
	var blocked := Muffle.blocked(get_world_3d().direct_space_state, from, to)
	if blocked:
		_muffled += 1
	return blocked


## The current AudioListener3D's position (the ears), else the current camera's, else null.
func _ears_position() -> Variant:
	if not is_inside_tree():
		return null
	var audio_listener := get_viewport().get_audio_listener_3d()
	if audio_listener != null:
		return audio_listener.global_position
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	return camera.global_position
