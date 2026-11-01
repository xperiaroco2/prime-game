class_name ShipEngineSounds
extends RefCounted
## When and where the ship's engine sounds (#1501; GDD §8 "The ship's engine"; ARCHITECTURE
## §4.7.64): SfxSet's six engine ids, from the own ClientModel (its ClientEngineBook, the console's
## ZoneProgress) and the client's own copy of the mode alone, never core/ state. ShipEngineViews
## asks due() each frame and hands each cue to WorldSounds as an EVENT, so every one is cut at its
## range from the ears and muffled behind the level like any world sound (SoundChooser):
## - the call: while the hologram calls (the engine off), a soft beep at each peak of its turbines'
##   pulse (ShipEngineHologram.PULSE_SECONDS), at the hologram;
## - the beep: at each lamp of an open breakers problem's order as the mimic board plays it
##   (ShipEngineViews' ORDER_STEP_SECONDS steps, none in its pause), at the hologram;
## - the wail: a problem opened (a new id in the book), once at each of its stations;
## - the blast: a new EngineBlast (the book's count), at the console, heard within FAR_RANGE_M;
## - the roar: the console's bar full (the engine done, its last ZoneProgress), at the console,
##   heard within FAR_RANGE_M; ShipEngineViews' `finished` fires with it, the finish's hook (#1502);
## - the zap: zap_at(), from a KnockedDown (no event names a short circuit, BreakerChain's: it is
##   the presser's KnockedDown alone): a player downed within reach of a tripped breaker still off.
## Edges only, seeded at the first frame: a view built again (a new level, a late join) plays no old
## problem, blast or finish. Outside the play phase (SoundChooser.in_play) nothing is due. Every
## sound, range and place is a placeholder, "not a decision".

## The pseudo-event a cue travels as (`id`: an SfxSet id, `position`: where it plays).
const EVENT := &"EngineSound"
## How far the blast and the roar carry (through the ship, over the party, GDD §8); the rest carry
## SoundChooser.HEARING_RANGE_M.
const FAR_RANGE_M := 40.0
## How far above a cue the muffle ray aims.
const AIM_M := 0.5
## Added to a breaker's reach (its kind's radius_m) for a downed body's place.
const ZAP_SLACK_M := 0.5
## How far above a breaker's floor a downed body may lie and still be its presser.
const ZAP_RISE_M := 2.5

var _seeded := false
var _pulse_seen := false
var _pulse := 0
## The open problems by id, and each breakers problem's last order step (absolute).
var _problems: Dictionary[int, bool] = {}
var _steps: Dictionary[int, int] = {}
var _blasts := 0
var _done := false


## The range a sound `id` carries.
static func range_of(id: StringName) -> float:
	if id == SfxSet.ENGINE_BLAST or id == SfxSet.ENGINE_ROAR:
		return FAR_RANGE_M
	return SoundChooser.HEARING_RANGE_M


## One cue: the EVENT's fields.
static func cue(id: StringName, at: Vector3) -> Dictionary:
	return {"id": id, "position": at}


## The cues due now, each an EVENT's fields: `console` the console's station id, `centre` the
## hologram's centre, `now` the host tick, `calling` whether the hologram calls (its called()).
func due(
	model: ClientModel, console: int, centre: Vector3, now: int, calling: bool
) -> Array[Dictionary]:
	var cues: Array[Dictionary] = []
	var station: ClientModel.Station = model.stations.get(console)
	if station == null:
		return cues
	var first := not _seeded
	_seeded = true
	if model.engine.blasts != _blasts:
		_blasts = model.engine.blasts
		cues.append(cue(SfxSet.ENGINE_BLAST, station.position + Vector3.UP))
	if station.done and not _done:
		cues.append(cue(SfxSet.ENGINE_ROAR, station.position + Vector3.UP))
	_done = station.done
	_wails(model, cues)
	_beeps(model, centre, now, cues)
	if calling:
		var pulse := floori(float(now) / Ticks.RATE / ShipEngineHologram.PULSE_SECONDS - 0.5)
		if _pulse_seen and pulse != _pulse:
			cues.append(cue(SfxSet.ENGINE_CALL, centre))
		_pulse = pulse
	_pulse_seen = calling
	if first or not SoundChooser.in_play(model):
		cues.clear()
	return cues


## Where a KnockedDown (`fields`) zaps: the nearest breaker of an open breakers problem, tripped and
## not yet on, within its reach of the downed body; null for any other knockdown (a hit, a blast,
## which takes every problem away first) or with no mode.
static func zap_at(fields: Dictionary, model: ClientModel, mode: GameMode) -> Variant:
	var body: Variant = fields.get("position")
	if not body is Vector3 or model == null:
		return null
	var at := body as Vector3
	var reach := -1.0
	for type: ShipEngine in ShipEngineClient.types_of(mode):
		for kind: ProblemKind in type.kinds:
			if kind is BreakersProblem:
				for fixture: StationKind in kind.fixtures:
					if fixture != null:
						reach = maxf(reach, fixture.radius_m + ZAP_SLACK_M)
	var found: Variant = null
	var best := reach
	for problem: ClientEngineBook.Problem in model.engine.problems.values():
		for i in range(problem.next, problem.breakers.size()):
			var breaker: ClientModel.Station = model.stations.get(problem.breakers[i])
			if breaker == null:
				continue
			var flat := Vector2(at.x - breaker.position.x, at.z - breaker.position.z).length()
			var rise := at.y - breaker.position.y
			if flat <= best and absf(rise) <= ZAP_RISE_M:
				best = flat
				found = breaker.position
	return found


func _wails(model: ClientModel, cues: Array[Dictionary]) -> void:
	var now_open: Dictionary[int, bool] = {}
	for id: int in model.engine.problems:
		now_open[id] = true
		if _problems.has(id):
			continue
		for site: int in model.engine.problems[id].stations:
			var station: ClientModel.Station = model.stations.get(site)
			if station != null:
				cues.append(cue(SfxSet.ENGINE_WAIL, station.position))
	_problems = now_open


func _beeps(model: ClientModel, centre: Vector3, now: int, cues: Array[Dictionary]) -> void:
	var step_ticks := maxi(1, Ticks.from_seconds(ShipEngineViews.ORDER_STEP_SECONDS))
	var steps: Dictionary[int, int] = {}
	for id: int in model.engine.problems:
		var order := model.engine.problems[id].breakers
		if order.is_empty():
			continue
		@warning_ignore("integer_division")
		var step := maxi(now, 0) / step_ticks
		steps[id] = step
		var lit := step % (order.size() + ShipEngineViews.ORDER_PAUSE_STEPS) < order.size()
		if _steps.has(id) and _steps[id] != step and lit:
			cues.append(cue(SfxSet.ENGINE_BEEP, centre))
	_steps = steps
