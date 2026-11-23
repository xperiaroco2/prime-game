class_name ShipEngineSounds
extends RefCounted
## When and where the ship's engine sounds (#1501; GDD §8 "The ship's engine"; ARCHITECTURE
## §4.7.64): SfxSet's five engine ids, from the own ClientModel (its ClientEngineBook, the console's
## ZoneProgress) and the client's own copy of the mode alone, never core/ state. ShipEngineViews
## asks due() each frame and hands each cue to WorldSounds as an EVENT, so every one is cut at its
## range from the ears and muffled behind the level like any world sound (SoundChooser):
## - the call: while the hologram calls (the engine off), a soft beep at each peak of its turbines'
##   pulse (ShipEngineHologram.PULSE_SECONDS), at the hologram;
## - the beep: at each lamp of an open breakers problem's order as the mimic board plays it
##   (ShipEngineViews' ORDER_STEP_SECONDS steps, none in its pause), at the hologram;
## - the wail: a problem opened (a new id in the book), once at each of its stations;
## - the blast: a new EngineBlast (the book's count), at the console, heard within FAR_RANGE_M;
## - the zap: zap_at(), from a KnockedDown (no event names a short circuit, BreakerChain's: it is
##   the presser's KnockedDown alone): a player downed within reach of a tripped breaker still off.
## - the M8 sounds (#1674), each an edge of the book between two frames:
##   - a problem gone with no blast (fixed): SfxSet.TASK_SUCCESS at each of its stations;
##   - a gill set's slit opened or shut again (`slits`): ENGINE_GILL_OPEN or ENGINE_GILL_SHUT at
##     its button;
##   - a breakers chain first seen: ENGINE_BREAKER_TRIP at each of its boards; `next` up:
##     ENGINE_BREAKER_ON at that breaker; down (a chain too late unwinds): ENGINE_BREAKER_TRIP at
##     the one that went off; the last one on's lamp turning green (its `since` plus the kind's
##     ramp, BreakersProblem.ramp_ticks): ENGINE_BREAKER_GREEN there;
##   - a socket's crystal laid in a charger: ENGINE_CRYSTAL_CHARGER there; its charge done
##     (CHARGING to WAITING): ENGINE_CHARGED there; fitted back into its socket (no item, no
##     charger, not a blast's return): ENGINE_CRYSTAL_SOCKET at the socket.
##   Pulling and taking a crystal are the pick-up's click (ItemPickedUp); the charge's loop is
##   StationHums'. Every event behind them reaches everyone and names no player.
## The engine's last stage sounds nothing of its own: it ends the round like any win (#1563).
## Edges only, seeded at the first frame: a view built again (a new level, a late join) plays no old
## problem or blast. Outside the play phase (SoundChooser.in_play) nothing is due. Every sound,
## range and place is a placeholder, "not a decision".

## The pseudo-event a cue travels as (`id`: an SfxSet id, `position`: where it plays).
const EVENT := &"EngineSound"
## How far the blast carries (through the ship, over the party, GDD §8); the rest carry
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
## The open problems by id (their stations), and each breakers problem's last order step (absolute).
var _problems: Dictionary[int, PackedInt32Array] = {}
var _steps: Dictionary[int, int] = {}
var _blasts := 0
## Each gill set's open slits, each breakers chain's `next` (-1: no chain yet) and the `since` whose
## green lamp sounded, and each socket's crystal (charger, phase, item), as at the last frame.
var _slits: Dictionary[int, int] = {}
var _nexts: Dictionary[int, int] = {}
var _greens: Dictionary[int, int] = {}
var _crystals: Dictionary[int, Vector3i] = {}


## The range a sound `id` carries.
static func range_of(id: StringName) -> float:
	if id == SfxSet.ENGINE_BLAST:
		return FAR_RANGE_M
	return SoundChooser.HEARING_RANGE_M


## One cue: the EVENT's fields.
static func cue(id: StringName, at: Vector3) -> Dictionary:
	return {"id": id, "position": at}


## The cues due now, each an EVENT's fields: `console` the console's station id, `centre` the
## hologram's centre, `now` the host tick, `calling` whether the hologram calls (its called()),
## `type` the client's own copy of the engine (its breakers' ramp; none: no green lamp sounds).
func due(
	model: ClientModel,
	console: int,
	centre: Vector3,
	now: int,
	calling: bool,
	type: ShipEngine = null
) -> Array[Dictionary]:
	var cues: Array[Dictionary] = []
	var station: ClientModel.Station = model.stations.get(console)
	if station == null:
		return cues
	var first := not _seeded
	_seeded = true
	var blasted := model.engine.blasts != _blasts
	if blasted:
		_blasts = model.engine.blasts
		cues.append(cue(SfxSet.ENGINE_BLAST, station.position + Vector3.UP))
	_fixes(model, blasted, cues)
	_wails(model, cues)
	_gills(model, cues)
	_breakers(model, now, _ramp_of(type), cues)
	_crystals_now(model, blasted, cues)
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
	var now_open: Dictionary[int, PackedInt32Array] = {}
	for id: int in model.engine.problems:
		now_open[id] = model.engine.problems[id].stations
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
	# Every order steps on the same clock: two open at once beep once, not twice on top.
	var beeped := false
	for id: int in model.engine.problems:
		var order := model.engine.problems[id].breakers
		if order.is_empty():
			continue
		@warning_ignore("integer_division")
		var step := maxi(now, 0) / step_ticks
		steps[id] = step
		var lit := step % (order.size() + ShipEngineViews.ORDER_PAUSE_STEPS) < order.size()
		if _steps.has(id) and _steps[id] != step and lit and not beeped:
			cues.append(cue(SfxSet.ENGINE_BEEP, centre))
			beeped = true
	_steps = steps


## A problem gone since the last frame with no blast in it was fixed: the success at each of its
## stations (a blast takes every problem away, fixed by nobody).
func _fixes(model: ClientModel, blasted: bool, cues: Array[Dictionary]) -> void:
	if blasted:
		return
	for id: int in _problems:
		if model.engine.problems.has(id):
			continue
		for site: int in _problems[id]:
			var station: ClientModel.Station = model.stations.get(site)
			if station != null:
				cues.append(cue(SfxSet.TASK_SUCCESS, station.position))


## Each gill set's slits opened or shut again since the last frame, at its button. A problem's open
## clears its sets' slits (ClientEngineBook): a set gone from the book is no shut.
func _gills(model: ClientModel, cues: Array[Dictionary]) -> void:
	for site: int in model.engine.slits:
		var now_open: int = model.engine.slits[site]
		var was_open: int = _slits.get(site, 0)
		var station: ClientModel.Station = model.stations.get(site)
		if station == null or now_open == was_open:
			continue
		if now_open & ~was_open:
			cues.append(cue(SfxSet.ENGINE_GILL_OPEN, station.position))
		if was_open & ~now_open:
			cues.append(cue(SfxSet.ENGINE_GILL_SHUT, station.position))
	_slits = model.engine.slits.duplicate()


## Each breakers chain's change since the last frame: tripped at its first sight (at its boards), a
## breaker on or gone off again, and the last one on's lamp turning green after `ramp` ticks (-1:
## none sounds).
func _breakers(model: ClientModel, now: int, ramp: int, cues: Array[Dictionary]) -> void:
	var nexts: Dictionary[int, int] = {}
	var greens: Dictionary[int, int] = {}
	for id: int in model.engine.problems:
		var problem := model.engine.problems[id]
		if problem.breakers.is_empty():
			continue
		nexts[id] = problem.next
		var was: int = _nexts.get(id, -1)
		if was < 0:
			for site: int in problem.stations:
				_cue_at(model, site, SfxSet.ENGINE_BREAKER_TRIP, cues)
		elif problem.next > was:
			_cue_at(model, problem.breakers[problem.next - 1], SfxSet.ENGINE_BREAKER_ON, cues)
		elif problem.next < was and problem.next < problem.breakers.size():
			_cue_at(model, problem.breakers[problem.next], SfxSet.ENGINE_BREAKER_TRIP, cues)
		if _greens.has(id):
			greens[id] = _greens[id]
		var lit := (
			problem.next > 0 and problem.since >= 0 and problem.next < problem.breakers.size()
		)
		if (
			ramp >= 0
			and lit
			and now >= problem.since + ramp
			and greens.get(id, -1) != problem.since
		):
			greens[id] = problem.since
			_cue_at(model, problem.breakers[problem.next - 1], SfxSet.ENGINE_BREAKER_GREEN, cues)
	_nexts = nexts
	_greens = greens


## Each socket's crystal's change since the last frame: laid in a charger, its charge done, fitted
## back into the socket (not a blast's return, `blasted`).
func _crystals_now(model: ClientModel, blasted: bool, cues: Array[Dictionary]) -> void:
	var seen: Dictionary[int, Vector3i] = {}
	for site: int in model.engine.crystals:
		var crystal := model.engine.crystals[site]
		var now := Vector3i(crystal.charger, crystal.phase, crystal.item)
		seen[site] = now
		var was: Vector3i = _crystals.get(site, Vector3i(-1, CrystalProblem.EMPTY, -1))
		if now.x >= 0 and was.x != now.x:
			_cue_at(model, now.x, SfxSet.ENGINE_CRYSTAL_CHARGER, cues)
		elif now.x >= 0 and was.y == CrystalProblem.CHARGING and now.y == CrystalProblem.WAITING:
			_cue_at(model, now.x, SfxSet.ENGINE_CHARGED, cues)
		elif now.x < 0 and now.z < 0 and was.z >= 0 and was.x < 0 and not blasted:
			_cue_at(model, site, SfxSet.ENGINE_CRYSTAL_SOCKET, cues)
	_crystals = seen


## A cue of sound `id` at station `site`, if the model knows it.
static func _cue_at(model: ClientModel, site: int, id: StringName, cues: Array[Dictionary]) -> void:
	var station: ClientModel.Station = model.stations.get(site)
	if station != null:
		cues.append(cue(id, station.position))


## The ramp of `type`'s breakers in ticks (its BreakersProblem kind), or -1 without one.
static func _ramp_of(type: ShipEngine) -> int:
	if type == null:
		return -1
	for kind: ProblemKind in type.kinds:
		var breakers := kind as BreakersProblem
		if breakers != null:
			return breakers.ramp_ticks()
	return -1
