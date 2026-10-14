class_name StationHums
extends Node3D
## The Generator's hum while it charges (#801, G6; ARCHITECTURE §4.7.53): one looping
## AudioStreamPlayer3D at each generator station the own ClientModel says is counting and not yet
## full, while the round plays (GameFlow.in_round: the hum stops with the round, a win or End).
## Only a Generator's generator kind hums (StationUse.is_generator): a zone held also counts, and
## stays silent. Cut and muffled like every world sound (WorldSounds): it plays only within
## SoundChooser.HEARING_RANGE_M of the ears (its `max_distance` the same), and one ray from the ears
## to SoundChooser.PANEL_AIM_M above the station every MUFFLE_EVERY_S lowers and dulls it behind the
## level (Muffle). Its stream is WorldSounds.hum_blip() until the engineer's file arrives.

## How often the muffle ray is cast for each hum playing (the ears move, unlike a one-shot's).
const MUFFLE_EVERY_S := 0.1
## How much quieter than a click the hum plays: a placeholder, "not a decision".
const HUM_DB := -6.0

var model: ClientModel
## The client's own copy of the mode: which station kinds are a Generator's generator.
var mode: GameMode
## The ears' position (WorldSounds.ears): called with no arguments, a Vector3, or null for none.
var ears := Callable()

## The hums playing, by station id, and each one's muffle.
var _hums: Dictionary[int, AudioStreamPlayer3D] = {}
var _muffles: Dictionary[int, Muffle] = {}
var _since_ray := 0.0
var _started := 0
var _rays := 0
var _stream: AudioStreamWAV = null


func _process(delta: float) -> void:
	var heard_from: Variant = ears.call() if ears.is_valid() else null
	var due := _due(heard_from)
	for id: int in _hums.keys():
		if not due.has(id):
			_stop(id)
	_since_ray += delta
	var cast := _since_ray >= MUFFLE_EVERY_S
	if cast:
		_since_ray = 0.0
	for id: int in due:
		if not _hums.has(id):
			_start(id, due[id])
			_muffle(id, heard_from as Vector3, 0.0)
		elif cast:
			_muffle(id, heard_from as Vector3, MUFFLE_EVERY_S)


## The station ids that hum now (counting, not full, a generator kind, in the round and within the
## hearing range of `heard_from`), each with its position.
func _due(heard_from: Variant) -> Dictionary[int, Vector3]:
	var due: Dictionary[int, Vector3] = {}
	if model == null or mode == null or not heard_from is Vector3 or not GameFlow.in_round(model):
		return due
	for id: int in model.stations:
		var station: ClientModel.Station = model.stations[id]
		if not station.counting or station.done or not StationUse.is_generator(mode, station.kind):
			continue
		if SoundChooser.audible(station.position, heard_from as Vector3):
			due[id] = station.position
	return due


## Stops every hum (the session ended or the level went).
func clear() -> void:
	for id: int in _hums.keys():
		_stop(id)


## The hums playing now (tests).
func hums() -> int:
	return _hums.size()


## How many hums were started (tests).
func started() -> int:
	return _started


## How many muffle rays were cast (tests).
func rays() -> int:
	return _rays


## The hum playing at station `id`, or null (tests).
func hum_of(id: int) -> AudioStreamPlayer3D:
	return _hums.get(id)


func _start(id: int, at: Vector3) -> void:
	if _stream == null:
		_stream = WorldSounds.hum_blip()
	var hum := AudioStreamPlayer3D.new()
	hum.name = "Hum%d" % id
	hum.stream = _stream
	hum.max_distance = SoundChooser.HEARING_RANGE_M
	hum.bus = AudioBuses.EFFECTS
	hum.volume_db = HUM_DB
	hum.position = at
	add_child(hum)
	hum.play()
	_hums[id] = hum
	_muffles[id] = Muffle.new()
	_started += 1


func _stop(id: int) -> void:
	var hum: AudioStreamPlayer3D = _hums[id]
	_hums.erase(id)
	_muffles.erase(id)
	remove_child(hum)
	hum.queue_free()


## Casts the muffle ray from `from` to the hum at `id` and eases its muffle over `delta` seconds
## (0: at once, as a one-shot starts).
func _muffle(id: int, from: Vector3, delta: float) -> void:
	var hum := _hums[id]
	var behind := false
	if is_inside_tree():
		_rays += 1
		var aim := hum.position + Vector3.UP * SoundChooser.PANEL_AIM_M
		behind = Muffle.blocked(get_world_3d().direct_space_state, from, to_global(aim))
	var muffle := _muffles[id]
	muffle.follow(behind, delta)
	hum.volume_db = HUM_DB + muffle.volume_db()
	hum.bus = muffle.bus_for(AudioBuses.EFFECTS)
