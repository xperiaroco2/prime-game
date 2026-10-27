class_name StationHums
extends Node3D
## The Generator's hum while it charges (#801, G6; ARCHITECTURE §4.7.54): one looping
## AudioStreamPlayer3D at each generator station the own ClientModel says is counting and not yet
## full, while the round plays (GameFlow.in_round: the hum stops with the round, a win or End).
## Only a Generator's generator kind hums (StationUse.is_generator): a zone held also counts, and
## stays silent. Cut and muffled like every world sound (WorldSounds): it plays only within
## SoundChooser.HEARING_RANGE_M of the ears (its `max_distance` the same), and one ray from the ears
## to SoundChooser.PANEL_AIM_M above the station every MUFFLE_EVERY_S lowers and dulls it behind the
## level (Muffle). Its stream is WorldSounds.hum_blip() until the engineer's file arrives.
## Cooking's grill sizzles the same way (#776, the cooking ADR's CD14 (a)) while a patty on it fries
## (CookingViews.ring_phase FRYING at the estimated host tick: GrillLoaded's ticks extrapolated, as
## the ring), and stops once it is fried (the ding; the task's error marks the burn) or taken
## off; its stream is WorldSounds.sizzle_blip(). The car repair's lift motor runs the same way
## (#811, RD14), at the car while its car rises (CarRepairUse.rising), keyed by the lift panel's id.

## How often the muffle ray is cast for each hum playing (the ears move, unlike a one-shot's).
const MUFFLE_EVERY_S := 0.1
## How much quieter than a click the hum plays: a placeholder, "not a decision".
const HUM_DB := -6.0
## The lift motor's pitch on the hum's placeholder (#811): a placeholder, "not a decision".
const MOTOR_PITCH := 0.6

var model: ClientModel
## The client's own copy of the mode: which station kinds are a Generator's generator.
var mode: GameMode
## The ears' position (WorldSounds.ears): called with no arguments, a Vector3, or null for none.
var ears := Callable()
## The estimated host tick now (AvatarViews.host_tick), for the grill's sizzle; unset: the model's.
var host_tick := Callable()

## The hums playing, by station id, and each one's muffle.
var _hums: Dictionary[int, AudioStreamPlayer3D] = {}
var _muffles: Dictionary[int, Muffle] = {}
var _since_ray := 0.0
var _started := 0
var _rays := 0
var _stream: AudioStreamWAV = null
var _sizzle: AudioStreamWAV = null


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


## The station ids that hum or sizzle now (a generator counting and not full, a grill whose patty
## fries; in the round and within the hearing range of `heard_from`), each with its position.
func _due(heard_from: Variant) -> Dictionary[int, Vector3]:
	var due: Dictionary[int, Vector3] = {}
	if model == null or mode == null or not heard_from is Vector3 or not GameFlow.in_round(model):
		return due
	var now := _now()
	for id: int in model.stations:
		var station: ClientModel.Station = model.stations[id]
		var motor_at: Variant = _motor_at(station, now)
		if motor_at is Vector3:
			if SoundChooser.audible(motor_at as Vector3, heard_from as Vector3):
				due[id] = motor_at as Vector3
			continue
		if not _sounds(station, now):
			continue
		if SoundChooser.audible(station.position, heard_from as Vector3):
			due[id] = station.position
	return due


## Whether `station` hums or sizzles at host tick `now`.
func _sounds(station: ClientModel.Station, now: int) -> bool:
	if _is_grill(station):
		return CookingViews.ring_phase(station, now) == CookingViews.Ring.FRYING
	return station.counting and not station.done and StationUse.is_generator(mode, station.kind)


## Where the car repair's lift motor runs for `station` at host tick `now` (#811, RD14): at the
## car, while `station` is its lift panel and the car rises (CarRepairUse.rising); else null.
func _motor_at(station: ClientModel.Station, now: int) -> Variant:
	var type := CarRepairUse.type_of(mode, station.kind)
	if type == null or CarRepairUse.role_of(type, station.kind) != CarRepairUse.Role.PANEL:
		return null
	if not CarRepairUse.rising(station, float(now), type.rise_ticks()):
		return null
	var car := CarRepairUse.station_of(model, type, CarRepairUse.Role.CAR)
	if car == null:
		return null
	return car.position


## Whether `station` is a Cooking's grill of the mode.
func _is_grill(station: ClientModel.Station) -> bool:
	var type := CookingUse.type_of(mode, station.kind)
	return type != null and CookingUse.role_of(type, station.kind) == CookingUse.Role.GRILL


func _now() -> int:
	if host_tick.is_valid():
		return host_tick.call() as int
	return model.host_tick_now.call() as int if model.host_tick_now.is_valid() else 0


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
	var hum := AudioStreamPlayer3D.new()
	if _is_grill(model.stations[id]):
		if _sizzle == null:
			_sizzle = WorldSounds.sizzle_blip()
		hum.name = "Sizzle%d" % id
		hum.stream = _sizzle
	elif _motor_at(model.stations[id], _now()) is Vector3:
		if _stream == null:
			_stream = WorldSounds.hum_blip()
		# The lift's motor: the hum's placeholder, lower (a look, not a decision).
		hum.name = "Motor%d" % id
		hum.stream = _stream
		hum.pitch_scale = MOTOR_PITCH
	else:
		if _stream == null:
			_stream = WorldSounds.hum_blip()
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
