class_name ShipEngineViews
extends Node3D
## The ship's engine in 3D, as stand-ins until the art track draws it (#1462, part 3 of #1225;
## ARCHITECTURE §9.5.27 "For part 3's client", §4.7.59): everything from the own ClientModel (its
## ClientEngineBook and the console's ZoneProgress), the estimated host tick and the client's own
## copy of the mode; nothing is predicted. While the engine is dealt (its console placed):
## - the console's hologram above its use spot: three stage strips, each filling with its third of
##   the bar (ZoneViews.ticks_at of the console's ZoneProgress), and the mimic board, a lamp per
##   breaker at its place in the ship scaled down round the console: red while tripped, green once
##   on, and the open chain's order played on it one lamp at a time, white (GDD §8: read it out or
##   remember it). It is the only place the order shows;
## - a red alarm lamp over each station an open problem holds (EngineProblemOpened until its
##   EngineProblemFixed or a blast);
## - a lamp over each breaker: red while tripped, yellow then green for the last one on (its ramp,
##   then its window, from BreakerChain's `since`), green for those before it; never the order;
## - a lamp over each charger: yellow while charging, green with a charged crystal waiting;
## - the level's gill sets (group `engine_gills`, each bound to the nearest gill button within
##   BIND_TOLERANCE_M): a slit shows `Open` or `Shut` (all open with no problem), and the white bar
##   `Light<n>` over the slit GillsProblem.BAR puts it at from the problem's opening tick;
## - a blast: an orange sphere swelling from the console and fading (EngineBlast).
## Every part is depth-tested and tells only public places and states; none names a player. The
## looks and sizes are placeholders, "not a decision".

## How far a gill set's Button may lie from its gill button's use spot, in metres.
const BIND_TOLERANCE_M := 1.5
## The hologram's centre over the console's use spot, and its scale of the ship.
const HOLOGRAM_LIFT_M := 1.9
const MIMIC_SCALE := 0.1
const MIMIC_LAMP_M := 0.06
## The stage strips: each one's length, height and the gap between them.
const STRIP_LENGTH_M := 0.5
const STRIP_HEIGHT_M := 0.05
const STRIP_GAP_M := 0.07
## A lamp over a station: its size and height over the use spot.
const LAMP_M := 0.12
const LAMP_LIFT_M := 2.0
## One step of the order played on the mimic board, and the dark steps after the last.
const ORDER_STEP_SECONDS := 0.6
const ORDER_PAUSE_STEPS := 2
## The blast's sphere: its seconds and its largest radius.
const BLAST_SECONDS := 0.8
const BLAST_RADIUS_M := 14.0
const DARK := Color(0.15, 0.15, 0.16)
const RED := Color(0.95, 0.15, 0.1)
const YELLOW := Color(0.95, 0.8, 0.1)
const GREEN := Color(0.2, 0.9, 0.3)
const WHITE := Color(0.95, 0.95, 0.95)
const CYAN := Color(0.2, 0.9, 0.95)
const BLAST := Color(1.0, 0.55, 0.15, 0.45)

var model: ClientModel
## The client's own copy of the mode: the engine's kinds and timings.
var mode: GameMode
## The estimated host tick now (AvatarViews.host_tick); unset: the newest snapshot's tick.
var host_tick := Callable()
## The level now (Game's), or null; a new one is searched for gill sets again.
var level: Node:
	set(value):
		level = value
		_gills.clear()
		_searched = false

var _searched := false
## The level's gill sets bound to a gill button's station id (-1 unbound).
var _gills: Dictionary[Node3D, int] = {}
## The drawn parts by station id: lamps, mimic lamps, the strips' fills.
var _lamps: Dictionary[int, MeshInstance3D] = {}
var _mimic: Dictionary[int, MeshInstance3D] = {}
var _fills: Array[MeshInstance3D] = []
var _strip_at: Array[Vector3] = []
var _console := -1
var _blast: MeshInstance3D
var _blast_left := 0.0
var _blasts_seen := 0
var _materials: Dictionary[Color, StandardMaterial3D] = {}


## The lamp drawn over station `id` (an alarm, a breaker's or a charger's), or null.
func lamp_of(id: int) -> MeshInstance3D:
	return _lamps.get(id)


## The mimic board's lamp of breaker station `id`, or null.
func mimic_of(id: int) -> MeshInstance3D:
	return _mimic.get(id)


## The fill of stage strip `index` (0 up), or null.
func strip_fill(index: int) -> MeshInstance3D:
	return _fills[index] if index < _fills.size() else null


## The colour a lamp shows now (its material's albedo), or DARK when hidden.
static func colour_of(lamp: MeshInstance3D) -> Color:
	if lamp == null or not lamp.visible or lamp.material_override == null:
		return DARK
	return (lamp.material_override as StandardMaterial3D).albedo_color


func clear() -> void:
	for child: Node in get_children():
		child.queue_free()
	_lamps.clear()
	_mimic.clear()
	_fills.clear()
	_strip_at.clear()
	_console = -1
	_blast = null
	_blast_left = 0.0
	_blasts_seen = 0
	for gills: Node3D in _gills:
		_gills[gills] = -1


func _process(delta: float) -> void:
	var type := _engine()
	if model == null or type == null:
		return
	var console := _station_of(type.start)
	if console != _console:
		clear()
		_console = console
		if console >= 0:
			_build(type)
	if _console < 0:
		return
	var now := _now()
	_draw_strips(now)
	_draw_lamps(type, now)
	_draw_gills(type, now)
	_draw_blast(delta)


func _engine() -> ShipEngine:
	var found := ShipEngineClient.types_of(mode)
	return found[0] if not found.is_empty() else null


func _now() -> int:
	if host_tick.is_valid():
		return host_tick.call() as int
	return model.snapshot_tick


## The first station of `kind`, or -1.
func _station_of(kind: StationKind) -> int:
	for id: int in _ids_of(kind):
		return id
	return -1


## The stations of `kind`, by id.
func _ids_of(kind: StationKind) -> Array[int]:
	var found: Array[int] = []
	if kind == null:
		return found
	for id: int in model.stations:
		if model.stations[id].kind == kind.id:
			found.append(id)
	found.sort()
	return found


func _build(type: ShipEngine) -> void:
	var centre := model.stations[_console].position + Vector3.UP * HOLOGRAM_LIFT_M
	var strips := maxi(1, type.stage_problems.size())
	for i in strips:
		var x := (i - (strips - 1) / 2.0) * (STRIP_LENGTH_M + STRIP_GAP_M)
		var back := _box(Vector3(STRIP_LENGTH_M, STRIP_HEIGHT_M, 0.02), DARK)
		back.position = centre + Vector3(x, 0.25, 0.0)
		var fill := _box(Vector3(STRIP_LENGTH_M, STRIP_HEIGHT_M, 0.03), CYAN)
		fill.position = back.position
		_fills.append(fill)
		_strip_at.append(back.position)
	for kind: ProblemKind in type.kinds:
		for site: int in _ids_of(kind.site):
			_lamps[site] = _box(Vector3.ONE * LAMP_M, RED, model.stations[site].position)
		for fixture: StationKind in kind.fixtures:
			for id: int in _ids_of(fixture):
				_lamps[id] = _box(Vector3.ONE * LAMP_M, DARK, model.stations[id].position)
				if kind is BreakersProblem:
					var at := model.stations[id].position - model.stations[_console].position
					var lamp := _box(Vector3.ONE * MIMIC_LAMP_M, DARK)
					lamp.position = centre + Vector3(at.x, 0.0, at.z) * MIMIC_SCALE
					_mimic[id] = lamp
	_blasts_seen = model.engine.blasts


func _box(size: Vector3, colour: Color, over := Vector3.INF) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = _material(colour)
	if over != Vector3.INF:
		part.position = over + Vector3.UP * LAMP_LIFT_M
	add_child(part)
	return part


func _material(colour: Color) -> StandardMaterial3D:
	if not _materials.has(colour):
		var made := StandardMaterial3D.new()
		made.albedo_color = colour
		made.emission_enabled = true
		made.emission = colour
		if colour.a < 1.0:
			made.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			made.cull_mode = BaseMaterial3D.CULL_DISABLED
			made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[colour] = made
	return _materials[colour]


func _draw_strips(now: int) -> void:
	var console: ClientModel.Station = model.stations.get(_console)
	var share := ZoneViews.fill(console, now) if console != null else 0.0
	var strips := _fills.size()
	for i in strips:
		var part := clampf(share * strips - i, 0.0, 1.0)
		_fills[i].visible = part > 0.0
		# Grown from the strip's left end (the fill's scale 0 is singular).
		_fills[i].scale = Vector3(maxf(part, 0.001), 1.0, 1.0)
		_fills[i].position = _strip_at[i] + Vector3.LEFT * STRIP_LENGTH_M * (1.0 - part) / 2.0


func _draw_lamps(type: ShipEngine, now: int) -> void:
	for id: int in _lamps:
		_lamps[id].visible = false
	for lamp: MeshInstance3D in _mimic.values():
		_light(lamp, DARK)
	for kind: ProblemKind in type.kinds:
		for site: int in _ids_of(kind.site):
			_lamps[site].visible = model.engine.problem_at(site) != null
		if kind is BreakersProblem:
			_draw_breakers(kind as BreakersProblem, now)
	for socket: int in model.engine.crystals:
		var crystal: ClientEngineBook.Crystal = model.engine.crystals[socket]
		var charger: MeshInstance3D = _lamps.get(crystal.charger)
		if charger == null:
			continue
		if crystal.phase == CrystalProblem.CHARGING:
			_light(charger, YELLOW)
		elif crystal.phase == CrystalProblem.WAITING:
			_light(charger, GREEN)


func _draw_breakers(kind: BreakersProblem, now: int) -> void:
	for problem: ClientEngineBook.Problem in model.engine.problems.values():
		var order := problem.breakers
		for i in order.size():
			var colour := RED
			if i < problem.next:
				colour = GREEN
				var last := i == problem.next - 1
				if last and problem.since >= 0 and now - problem.since < kind.ramp_ticks():
					colour = YELLOW
			var lamp: MeshInstance3D = _lamps.get(order[i])
			if lamp != null:
				_light(lamp, colour)
			var mimic: MeshInstance3D = _mimic.get(order[i])
			if mimic != null:
				_light(mimic, RED if colour == RED else GREEN)
		if order.is_empty():
			continue
		# The order, played on the mimic board alone: one lamp a step, then a pause.
		var step_ticks := maxi(1, Ticks.from_seconds(ORDER_STEP_SECONDS))
		@warning_ignore("integer_division")
		var step := (maxi(now, 0) / step_ticks) % (order.size() + ORDER_PAUSE_STEPS)
		if step < order.size() and _mimic.has(order[step]):
			_light(_mimic[order[step]], WHITE)


func _light(lamp: MeshInstance3D, colour: Color) -> void:
	lamp.visible = true
	lamp.material_override = _material(colour)


func _draw_gills(type: ShipEngine, now: int) -> void:
	var gills_kind: GillsProblem = null
	for kind: ProblemKind in type.kinds:
		if kind is GillsProblem:
			gills_kind = kind as GillsProblem
	if gills_kind == null or level == null or not is_instance_valid(level):
		return
	if not _searched:
		_searched = true
		for found: Node in level.get_tree().get_nodes_in_group(&"engine_gills"):
			if found is Node3D and level.is_ancestor_of(found):
				_gills[found as Node3D] = -1
	for gills: Node3D in _gills:
		if _gills[gills] < 0:
			_gills[gills] = _bind_gills(gills, gills_kind)
		var station := _gills[gills]
		var problem := model.engine.problem_at(station) if station >= 0 else null
		var open: int = model.engine.slits.get(station, 0)
		var bar := -1
		if problem != null:
			var opened := ClientEngineBook.opened_tick(problem, gills_kind)
			@warning_ignore("integer_division")
			var steps := maxi(0, now - opened) / gills_kind.step_ticks()
			bar = GillsProblem.BAR[steps % GillsProblem.BAR.size()]
		for slit: int in GillsProblem.SLITS:
			var shown_open := problem == null or (open & (1 << slit)) != 0
			_show(gills, "Slit%d/Open" % (slit + 1), shown_open)
			_show(gills, "Slit%d/Shut" % (slit + 1), not shown_open)
			_show(gills, "Light%d" % (slit + 1), slit == bar)


func _bind_gills(gills: Node3D, kind: GillsProblem) -> int:
	var button := gills.get_node_or_null(^"Button") as Node3D
	var from := button.global_position if button != null else gills.global_position
	var best := -1
	var best_m := BIND_TOLERANCE_M
	for id: int in _ids_of(kind.site):
		var spot := model.stations[id].position
		var apart := Vector2(spot.x - from.x, spot.z - from.z).length()
		if apart <= best_m:
			best = id
			best_m = apart
	return best


func _show(under: Node3D, path: String, shown: bool) -> void:
	var part := under.get_node_or_null(path) as Node3D
	if part != null:
		part.visible = shown


func _draw_blast(delta: float) -> void:
	if model.engine.blasts != _blasts_seen:
		_blasts_seen = model.engine.blasts
		_blast_left = BLAST_SECONDS
		if _blast == null:
			var sphere := SphereMesh.new()
			_blast = MeshInstance3D.new()
			_blast.mesh = sphere
			_blast.material_override = _material(BLAST)
			add_child(_blast)
		_blast.position = model.stations[_console].position + Vector3.UP
	if _blast == null:
		return
	_blast_left = maxf(0.0, _blast_left - delta)
	_blast.visible = _blast_left > 0.0
	var grown := 1.0 - _blast_left / BLAST_SECONDS
	_blast.scale = Vector3.ONE * maxf(0.001, grown * BLAST_RADIUS_M * 2.0)
