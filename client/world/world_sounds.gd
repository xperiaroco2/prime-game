class_name WorldSounds
extends Node3D
## Plays the world sounds (ARCHITECTURE §4.7, §4.7.38; the M4 ADR's D9, E33 (a); M4-8; #525): for
## each event SoundChooser picks within the hearing range of the ears (E40's amendment of E33:
## the current AudioListener3D, LifeView's Ears), a one-shot AudioStreamPlayer3D at its place on
## the Effects bus (D15), with `max_distance` the same range, freed when it ends.
## As it starts, one ray from the ears to the sound's aim (SoundChooser.SWING_AIM_M or ITEM_AIM_M
## above it) against the world layer of the client's own level (the M5 ADR §1.6, E42 (a), D13 (a);
## M5-7): behind the level it plays muffled (Muffle: 8 dB quieter, on the muffled Effects bus's
## low-pass), and stays so to its end.
##
## Footsteps (#525), each physics frame: of the local player while it is living,
## from how far it moved (is_on_floor() flickers on stairs: only FootstepSurface's ray decides the
## floor); of every other player this client draws while the model knows it living
## (not downed, dead or gone), from how far its interpolated pose moved (never a claimed
## velocity). FootstepCadence says when a step falls; SoundChooser.step cuts it beyond the hearing
## range before any ray; FootstepSurface's ray down finds the floor's surface, and no floor (a
## jump) plays none. Another player's step casts the muffle ray to SoundChooser.STEP_AIM_M above
## its feet; the own steps cast none (nothing stands between the ears and the own feet).
## The streams are SfxSet's: Kenney's CC0 files, each id a randomizer.

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

var _played := 0
var _rays := 0
var _muffled := 0
var _steps := 0
## Where each player's feet were in the last physics frame, and its cadence; the own player's
## under 0 (no peer is 0).
var _feet: Dictionary[int, Vector3] = {}
var _cadences: Dictionary[int, FootstepCadence] = {}


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
	var sound := SoundChooser.choose(event_name, fields, model, position_of, heard_from as Vector3)
	if sound == null:
		return
	_start(sound, sfx.stream_for(sound.id), heard_from as Vector3, true)


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


## Where `peer` is as this client draws it: the local player, or another player's body; null when
## the client draws no such player.
func position_of(peer: int) -> Variant:
	if model != null and peer == model.own_peer and player != null and player.is_inside_tree():
		return player.global_position
	var body := avatars.body_of(peer) if avatars != null else null
	if body == null or not body.is_inside_tree():
		return null
	return body.global_position


func _physics_process(delta: float) -> void:
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
		if due and heard_from is Vector3:
			_step(at, heard_from as Vector3, peer != 0)


## The movement numbers of `peer`'s steps (0: the own player): the client's own copy of the mode's.
func _rules_of(peer: int) -> PlayerRules:
	if peer == 0:
		return player.rules
	return avatars.rules


## A footstep of feet at `at` heard from `heard_from`, muffled by the level if `occlude`.
func _step(at: Vector3, heard_from: Vector3, occlude: bool) -> void:
	var sound := SoundChooser.step(at, heard_from)
	if sound == null:
		return
	var surface: Variant = FootstepSurface.DEFAULT
	if is_inside_tree():
		surface = FootstepSurface.under(get_world_3d().direct_space_state, at)
	if surface == null:
		return
	if _start(sound, sfx.stream_for(SfxSet.footstep(surface as StringName)), heard_from, occlude):
		_steps += 1


## Starts `sound` with `stream`, muffled if `occlude` and the level is in the way; false (and
## nothing started) with no stream.
func _start(
	sound: SoundChooser.Sound, stream: AudioStream, heard_from: Vector3, occlude: bool
) -> bool:
	if stream == null:
		return false
	var sound_player := AudioStreamPlayer3D.new()
	sound_player.name = "Sound%d" % _played
	sound_player.stream = stream
	sound_player.max_distance = SoundChooser.HEARING_RANGE_M
	var muffle := Muffle.new()
	muffle.follow(occlude and _blocked(heard_from, sound.aim), 0.0)
	sound_player.volume_db = muffle.volume_db()
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
	var ears := get_viewport().get_audio_listener_3d()
	if ears != null:
		return ears.global_position
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	return camera.global_position
