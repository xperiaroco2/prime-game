class_name ShipEngineViews
extends Node3D
## The ship's engine in 3D, as stand-ins until the art track draws it (#1462, part 3 of #1225;
## ARCHITECTURE §9.5.27 "For part 3's client", §4.7.59): everything from the own ClientModel (its
## ClientEngineBook and the console's ZoneProgress), the estimated host tick and the client's own
## copy of the mode; nothing is predicted. While the engine is dealt (its console placed):
## - the console's hologram at the level's point for it (a Node3D in group `engine_hologram`, over
##   the console itself, which its use spot faces), else above its use spot: a stage strip per
##   stage (the engine's TaskState total), each filling with its share of the bar (ZoneViews.fill
##   of the console's ZoneProgress),
##   and the mimic board, a lamp per breaker at its place in the ship scaled down round the
##   console: red while tripped, green once on, and the open chain's order played on it one lamp
##   at a time, white (GDD §8: read it out or remember it). It is the only place the order shows;
## - a red alarm lamp over each station an open problem holds (EngineProblemOpened until its
##   EngineProblemFixed or a blast);
## - a lamp over each breaker: red while tripped, yellow then green for the last one on (its ramp,
##   then its window, from BreakerChain's `since`), green for those before it; never the order;
## - a lamp over each charger: yellow while charging, green with a charged crystal waiting;
## - the level's gill sets (group `engine_gills`, each bound to the nearest gill button within
##   BIND_TOLERANCE_M): a slit shows `Open` or `Shut` (all open with no problem), and the white bar
##   `Light<n>` over the slit GillsProblem.BAR puts it at from the problem's opening tick;
## - at a gill set, a puff of steam at each slit a press opens while a problem holds it, and a
##   cloud of mist over the five when all five open fix it (GDD §8; edges seen frame to frame,
##   seeded when the set is first bound, so a view built again plays none; a blast plays none);
## - the hologram made readable (ShipEngineHologram, #1500): the call while the engine is off, the
##   turbines' spin (the turbines and the start button at the places the level gives under
##   the hologram's point, `Turbine<n>` and `Button`, #1499), the ring of the bar round its disc,
##   a point and a line of light per site station and the countdown to the nearest problem's
##   deadline;
## - a blast: an orange sphere swelling from the console and fading (EngineBlast);
## - the engine's sounds (#1501, ShipEngineSounds): each cue due this frame goes out as
##   `sound_due` (ItemWorld hands it to WorldSounds), and the roar's with `finished`;
## - the finish (#1502, ShipEngineFinale): at the roar, the flame from the art ship's nozzles and
##   the light show over the hologram, for the round's linger.
## Every part is depth-tested and tells only public places and states; none names a player. The
## looks and sizes are placeholders, "not a decision".

## An engine sound due now (ShipEngineSounds.EVENT and its cue), for WorldSounds.on_event.
signal sound_due(event_name: StringName, fields: Dictionary)
## The engine finished in play (the roar's moment, at the console): the finish's flame and light
## show start with it (#1502).
signal finished(at: Vector3)

## How far a gill set's Button may lie from its gill button's use spot, in metres.
const BIND_TOLERANCE_M := 1.5
## The hologram's centre over the console's use spot when the level gives no point for it, and its
## scale of the ship.
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
## A puff of steam at a slit: its seconds, its largest radius and how far it rises.
const STEAM_SECONDS := 0.8
const STEAM_RADIUS_M := 0.25
const STEAM_RISE_M := 0.5
## The cloud of mist over a gill set: its seconds and its largest radius.
const MIST_SECONDS := 3.0
const MIST_RADIUS_M := 1.2
const VAPOUR := Color(0.92, 0.95, 1.0, 0.6)

var model: ClientModel
## The client's own copy of the mode: the engine's kinds and timings.
var mode: GameMode
## The estimated host tick now (AvatarViews.host_tick); unset: the newest snapshot's tick.
var host_tick := Callable()
## The level now (Game's), or null; a new one is searched for gill sets again, and a drawn
## engine is drawn again for its hologram point.
var level: Node:
	set(value):
		level = value
		if _console >= 0:
			clear()
		_gills.clear()
		_searched = false

var _searched := false
## The level's gill sets bound to a gill button's station id (-1 unbound).
var _gills: Dictionary[Node3D, int] = {}
## The drawn parts by station id: lamps, mimic lamps, the strips' fills.
var _lamps: Dictionary[int, MeshInstance3D] = {}
var _mimic: Dictionary[int, MeshInstance3D] = {}
var _backs: Array[MeshInstance3D] = []
var _fills: Array[MeshInstance3D] = []
var _strip_at: Array[Vector3] = []
var _console := -1
var _blast: MeshInstance3D
var _blast_left := 0.0
var _blasts_seen := 0
var _materials: Dictionary[Color, StandardMaterial3D] = {}
var _hologram: ShipEngineHologram
var _centre := Vector3.ZERO
## The finish (#1502): built with the engine, started by the roar.
var _finale: ShipEngineFinale
## The engine's sounds' edges, seeded anew with each build.
var _sounds := ShipEngineSounds.new()
## The gills' puffs and clouds, under one node of their own, each with its seconds left.
var _vapour: Node3D
var _steam: Dictionary[MeshInstance3D, float] = {}
var _mist: Dictionary[MeshInstance3D, float] = {}
## Per bound gill button's station: its open slits and whether a problem held it last frame.
var _was_open: Dictionary[int, int] = {}
var _was_held: Dictionary[int, bool] = {}
## The station devices' looks (#1550), bound with the engine; null before.
var _looks: ShipStationLooks


## The hologram made readable, or null before the console is placed.
func hologram() -> ShipEngineHologram:
	return _hologram


## The station devices' looks, or null before the console is placed.
func station_looks() -> ShipStationLooks:
	return _looks


## The puffs of steam showing now.
func steam() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	found.assign(_steam.keys())
	return found


## The clouds of mist showing now.
func mist() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	found.assign(_mist.keys())
	return found


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
	_backs.clear()
	_fills.clear()
	_strip_at.clear()
	_console = -1
	_blast = null
	_blast_left = 0.0
	_blasts_seen = 0
	_hologram = null
	_looks = null
	_finale = null
	_sounds = ShipEngineSounds.new()
	_vapour = null
	_steam.clear()
	_mist.clear()
	_was_open.clear()
	_was_held.clear()
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
	# A blast this frame took its problems away: nothing of them was fixed.
	var blasted := model.engine.blasts != _blasts_seen
	var share := _draw_strips(type, now)
	_hologram.update(now, share, delta, blasted)
	_looks.update(now, delta, _hologram, share, _order_lit(now), blasted)
	for cue: Dictionary in _sounds.due(model, _console, _centre, now, _hologram.called()):
		sound_due.emit(ShipEngineSounds.EVENT, cue)
		if cue["id"] == SfxSet.ENGINE_ROAR:
			finished.emit(cue["position"] as Vector3)
			var nozzles := ShipEngineFinale.nozzles_of(level if is_instance_valid(level) else null)
			_finale.start(_centre, nozzles, ShipEngineFinale.seconds_of(mode))
	_finale.update(delta)
	_draw_lamps(type, now)
	_draw_gills(type, now, blasted)
	_draw_vapour(delta)
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
	var centre := _hologram_centre()
	_centre = centre
	# The devices first: a station whose device shows it draws no stand-in, and the art console
	# replaces the mimic board, the strips (while they are its three) and the hologram's look.
	_looks = ShipStationLooks.new()
	_looks.bind(model, type, level if is_instance_valid(level) else null, _console)
	var art := _looks.console() != null
	_build_strips(_strip_count(type))
	var sites: Array[int] = []
	for kind: ProblemKind in type.kinds:
		for site: int in _ids_of(kind.site):
			if not _looks.has_art(site):
				_lamps[site] = _box(Vector3.ONE * LAMP_M, RED, model.stations[site].position)
			if not sites.has(site):
				sites.append(site)
		for fixture: StationKind in kind.fixtures:
			for id: int in _ids_of(fixture):
				if not _looks.has_art(id):
					_lamps[id] = _box(Vector3.ONE * LAMP_M, DARK, model.stations[id].position)
				if kind is BreakersProblem and not art:
					var at := model.stations[id].position - model.stations[_console].position
					var lamp := _box(Vector3.ONE * MIMIC_LAMP_M, DARK)
					lamp.position = centre + Vector3(at.x, 0.0, at.z) * MIMIC_SCALE
					_mimic[id] = lamp
	_hologram = ShipEngineHologram.new()
	add_child(_hologram)
	_finale = ShipEngineFinale.new()
	add_child(_finale)
	var point := _hologram_point()
	_hologram.setup(model, _console, centre, sites, _turbine_places(point), _button_place(point))
	# The state readers stay (called(), nearest_deadline()); the art console draws them.
	_hologram.visible = not art
	_vapour = Node3D.new()
	add_child(_vapour)
	_blasts_seen = model.engine.blasts


## The stages the bar is split in: the engine's TaskState total (the `engine_stages` setting, the
## N of the bar_ticks(N) its ZoneProgress `needed` is), else, before that comes, `stage_problems`'.
func _stages(type: ShipEngine) -> int:
	for task: ClientModel.Task in model.tasks.values():
		if task.type == type.id and task.total > 0:
			return task.total
	return maxi(1, type.stage_problems.size())


## The stand-in strips to draw: none while the art console's three show the stages.
func _strip_count(type: ShipEngine) -> int:
	var stages := _stages(type)
	if _looks != null and _looks.console() != null and stages == ShipConsoleLook.STRIPS:
		return 0
	return stages


## A strip per stage side by side over the hologram's centre, drawn anew when the count changes.
func _build_strips(strips: int) -> void:
	for part: MeshInstance3D in _backs + _fills:
		part.queue_free()
	_backs.clear()
	_fills.clear()
	_strip_at.clear()
	var centre := _hologram_centre()
	for i in strips:
		var x := (i - (strips - 1) / 2.0) * (STRIP_LENGTH_M + STRIP_GAP_M)
		var back := _box(Vector3(STRIP_LENGTH_M, STRIP_HEIGHT_M, 0.02), DARK)
		back.position = centre + Vector3(x, 0.25, 0.0)
		var fill := _box(Vector3(STRIP_LENGTH_M, STRIP_HEIGHT_M, 0.03), CYAN)
		fill.position = back.position
		_backs.append(back)
		_fills.append(fill)
		_strip_at.append(back.position)


## The first Node3D of the level in group `engine_hologram`, else HOLOGRAM_LIFT_M over the
## console's use spot (a player standing on the spot would have it over the head).
func _hologram_centre() -> Vector3:
	var point := _hologram_point()
	if point != null:
		return point.global_position
	return model.stations[_console].position + Vector3.UP * HOLOGRAM_LIFT_M


## The first Node3D of the level in group `engine_hologram`, or null.
func _hologram_point() -> Node3D:
	if level != null and is_instance_valid(level) and level.is_inside_tree():
		for found: Node in level.get_tree().get_nodes_in_group(&"engine_hologram"):
			if found is Node3D and level.is_ancestor_of(found):
				return found as Node3D
	return null


## The places of the hologram's turbines the level gives under its point (#1499): each Node3D
## child named `Turbine<n>`, in name order; none, the hologram's stand-ins.
func _turbine_places(point: Node3D) -> Array[Vector3]:
	var places: Array[Vector3] = []
	if point == null:
		return places
	var named: Array[Node3D] = []
	for child: Node in point.get_children():
		if child is Node3D and str(child.name).begins_with("Turbine"):
			named.append(child as Node3D)
	named.sort_custom(func(a: Node3D, b: Node3D) -> bool: return str(a.name) < str(b.name))
	for turbine: Node3D in named:
		places.append(turbine.global_position)
	return places


## The place of the hologram's start button the level gives under its point (#1499): its Node3D
## child `Button`; none, Vector3.INF (the hologram's stand-in).
func _button_place(point: Node3D) -> Vector3:
	var button := point.get_node_or_null(^"Button") as Node3D if point != null else null
	return button.global_position if button != null else Vector3.INF


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


## Fills the strips with the bar at host tick `now` and gives its share (0 to 1).
func _draw_strips(type: ShipEngine, now: int) -> float:
	if _strip_count(type) != _fills.size():
		_build_strips(_strip_count(type))
	var console: ClientModel.Station = model.stations.get(_console)
	var share := ZoneViews.fill(console, now) if console != null else 0.0
	var strips := _fills.size()
	for i in strips:
		var part := clampf(share * strips - i, 0.0, 1.0)
		_fills[i].visible = part > 0.0
		# Grown from the strip's left end (the fill's scale 0 is singular).
		_fills[i].scale = Vector3(maxf(part, 0.001), 1.0, 1.0)
		_fills[i].position = _strip_at[i] + Vector3.LEFT * STRIP_LENGTH_M * (1.0 - part) / 2.0
	return share


func _draw_lamps(type: ShipEngine, now: int) -> void:
	for id: int in _lamps:
		_lamps[id].visible = false
	for lamp: MeshInstance3D in _mimic.values():
		_light(lamp, DARK)
	for kind: ProblemKind in type.kinds:
		for site: int in _ids_of(kind.site):
			var alarm: MeshInstance3D = _lamps.get(site)
			if alarm != null:
				alarm.visible = model.engine.problem_at(site) != null
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
		var step := order_step(order.size(), now)
		if step >= 0 and _mimic.has(order[step]):
			_light(_mimic[order[step]], WHITE)


## The step of an order of `size` breakers that plays at host tick `now` (one a step, then a
## pause), or -1 in the pause.
static func order_step(size: int, now: int) -> int:
	if size <= 0:
		return -1
	var step_ticks := maxi(1, Ticks.from_seconds(ORDER_STEP_SECONDS))
	@warning_ignore("integer_division")
	var step := (maxi(now, 0) / step_ticks) % (size + ORDER_PAUSE_STEPS)
	return step if step < size else -1


## The breaker station the art console's one order lamp lights at host tick `now`, or -1. Two
## chains can be open at once (one per board): their orders take turns, by problem id, each played
## with its own pause after it, so none waits on the other's fix.
func _order_lit(now: int) -> int:
	var orders: Array[PackedInt32Array] = []
	var ids: Array[int] = []
	ids.assign(model.engine.problems.keys())
	ids.sort()
	for id: int in ids:
		var problem: ClientEngineBook.Problem = model.engine.problems[id]
		if not problem.breakers.is_empty():
			orders.append(problem.breakers)
	return order_turn(orders, now)


## The breaker of `orders` that plays at host tick `now` when they take turns on one lamp (each
## order a step a breaker, then ORDER_PAUSE_STEPS, then the next order), or -1 in a pause.
static func order_turn(orders: Array[PackedInt32Array], now: int) -> int:
	var cycle := 0
	for order: PackedInt32Array in orders:
		cycle += order.size() + ORDER_PAUSE_STEPS
	if cycle == 0:
		return -1
	var step_ticks := maxi(1, Ticks.from_seconds(ORDER_STEP_SECONDS))
	@warning_ignore("integer_division")
	var step := (maxi(now, 0) / step_ticks) % cycle
	for order: PackedInt32Array in orders:
		if step < order.size():
			return order[step]
		step -= order.size() + ORDER_PAUSE_STEPS
		if step < 0:
			return -1
	return -1


func _light(lamp: MeshInstance3D, colour: Color) -> void:
	lamp.visible = true
	lamp.material_override = _material(colour)


func _draw_gills(type: ShipEngine, now: int, blasted: bool) -> void:
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
		if station >= 0:
			_puff_gills(gills, station, problem != null, open, blasted)


## The steam and the mist of gill set `gills` (its button's station `station`), from the change
## since the last frame: a slit newly open while a problem held the set puffs; the problem gone with
## all five open (fixed, not blasted) leaves a cloud. The first look at a set only remembers it.
func _puff_gills(gills: Node3D, station: int, held: bool, open: int, blasted: bool) -> void:
	if _was_open.has(station) and not blasted:
		var was_held := _was_held[station]
		if held or was_held:
			var opened := open & ~_was_open[station]
			for slit: int in GillsProblem.SLITS:
				if (opened & (1 << slit)) != 0:
					var cut := gills.get_node_or_null("Slit%d" % (slit + 1)) as Node3D
					_steam[_vapour_at(cut if cut != null else gills)] = STEAM_SECONDS
		if was_held and not held and open == GillsProblem.ALL_OPEN:
			_mist[_vapour_at(gills, _slits_middle(gills))] = MIST_SECONDS
	_was_open[station] = open
	_was_held[station] = held


## The middle of gill set `gills`' slits, else the set's own place.
func _slits_middle(gills: Node3D) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for slit: int in GillsProblem.SLITS:
		var cut := gills.get_node_or_null("Slit%d" % (slit + 1)) as Node3D
		if cut != null:
			sum += cut.global_position
			count += 1
	return sum / count if count > 0 else gills.global_position


## A puff or a cloud at `at` (else at `over`'s place), with a material of its own to fade.
func _vapour_at(over: Node3D, at := Vector3.INF) -> MeshInstance3D:
	var look := StandardMaterial3D.new()
	look.albedo_color = VAPOUR
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var part := MeshInstance3D.new()
	part.mesh = SphereMesh.new()
	part.material_override = look
	_vapour.add_child(part)
	part.global_position = at if at != Vector3.INF else over.global_position
	part.scale = Vector3.ONE * 0.001
	return part


## Each puff swells, rises and fades over STEAM_SECONDS, each cloud over MIST_SECONDS; then freed.
func _draw_vapour(delta: float) -> void:
	for part: MeshInstance3D in _steam.keys():
		_steam[part] -= delta
		_fade(
			part, _steam[part], STEAM_SECONDS, STEAM_RADIUS_M, STEAM_RISE_M * delta / STEAM_SECONDS
		)
		if _steam[part] <= 0.0:
			_steam.erase(part)
	for part: MeshInstance3D in _mist.keys():
		_mist[part] -= delta
		_fade(part, _mist[part], MIST_SECONDS, MIST_RADIUS_M, 0.0)
		if _mist[part] <= 0.0:
			_mist.erase(part)


func _fade(part: MeshInstance3D, left: float, seconds: float, radius: float, rise: float) -> void:
	if left <= 0.0:
		part.queue_free()
		return
	var grown := 1.0 - left / seconds
	part.scale = Vector3.ONE * maxf(0.001, sqrt(grown) * radius * 2.0)
	part.position.y += rise
	var look := part.material_override as StandardMaterial3D
	look.albedo_color = Color(VAPOUR, VAPOUR.a * left / seconds)


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
