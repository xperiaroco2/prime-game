class_name CarRepairViews
extends Node3D
## The car repair's station scenes in the level, driven from the own ClientModel (#811, the car
## repair ADR's §8 R7, RE8, RE16, RD3; ARCHITECTURE §4.7.56). The level holds R5's scenes
## (`levels/stations/car.tscn`, `lift_panel.tscn`, `part_picture.tscn`, `parts_shelf.tscn` with its
## three bins), each found by its `UseSpot` in the `spawn_<tag>` group of its kind; a placed station
## binds to the scene of its kind whose use spot is nearest in 3D, within
## StationViews.BIND_TOLERANCE_M. A bin's scene is the shelf's `BinN`, the use spot's parent.
##
## - The car's `Lift` (an AnimatableBody3D on the `movers` layer) stands at its rest height plus
##   CarRepairUse.lift_fraction() of its rise: the hull's underside then reaches the type's
##   `clearance_m` above the use spot fully up (the hull's lowest point read once from its boxes).
##   Moved in the physics step, so the own player's capsule meets it there (RE8). Unbound: lowered.
##   The car itself is never hidden: it is a big prop, and its height is every client's to know.
## - The panel's `Light` shows `up` (LiftChanged) and nothing else: no fitter, fit tick or fitted
##   count reaches the panel (RE16, RD14 (a)).
## - The wall picture's `Picture` quad shows the part PartNeeded names, with the very material of
##   the plate on that part's bin (RD3: the same picture), found through CarRepair.bin_of() and the
##   bin's bound scene; a bin no scene binds: a fallback colour by the part's index (a look, not a
##   decision). No part needed: hidden.
## The lamp and the picture move once per scene under a StationViews.StationSight wrapper in
## SightHider's group (render checklist item 3): nothing here sets the wrapper's `visible`.

const WRAPPER := StationViews.WRAPPER
## The fallback picture colours for a part whose bin no scene binds: a look, not a decision.
const FALLBACK: Array[Color] = [
	Color(0.3, 0.7, 0.3), Color(0.3, 0.45, 0.85), Color(0.9, 0.8, 0.25), Color(0.8, 0.35, 0.3)
]

var model: ClientModel
## The client's own copy of the mode: its CarRepairs.
var mode: GameMode
## The estimated host tick now (AvatarViews.host_tick); unset: the model's host tick.
var host_tick := Callable()
## The level now (Game's), or null; a new one is searched for scenes again.
var level: Node:
	set(value):
		level = value
		_scenes.clear()
		_bound_ids.clear()

var _scenes: Array[Scene] = []
var _bound_ids: Array[int] = []
## The host tick last read and the seconds since it changed: the car moves between ticks.
var _tick := -1
var _since_tick := 0.0


## One station scene of the level.
class Scene:
	extends RefCounted

	var root: Node3D
	var spot: Node3D
	var type: CarRepair
	var kind: StationKind
	var role: CarRepairUse.Role
	var sight: StationViews.StationSight
	var station := -1
	## The car's lift body, its rest height and its rise to the clearance (car scenes only).
	var lift: Node3D
	var lift_rest_y := 0.0
	var rise_m := 0.0

	## A driven part, looked up under the wrapper only (it moved there at the first find).
	func part(path: String) -> Node3D:
		return sight.get_node_or_null(path) as Node3D if sight != null else null


## The station whose scene `body` collides for, while it is bound: a scene's `Collision`, and the
## car's `Lift` (its hull, up or down); -1 otherwise. `shape` is unused (ItemInteractions' form).
func station_of_hit(body: Object, _shape: int = -1) -> int:
	for scene: Scene in _scenes:
		if scene.station < 0 or not is_instance_valid(scene.root):
			continue
		if body == scene.root.get_node_or_null(^"Collision"):
			return scene.station
		if scene.lift != null and body == scene.lift:
			return scene.station
	return -1


## The bin whose shelf `body` is (the shelf's one `Collision` serves its three bins), the bound
## bin nearest `point` across the floor (the shelf's own turn does not matter); -1 for another
## body or no bound bin there.
func station_of_point(body: Object, point: Vector3) -> int:
	var best := -1
	var best_m := INF
	for scene: Scene in _scenes:
		if scene.role != CarRepairUse.Role.BIN or scene.station < 0:
			continue
		if not is_instance_valid(scene.root):
			continue
		var shelf := scene.root.get_parent()
		if shelf == null or body != shelf.get_node_or_null(^"Collision"):
			continue
		var at := scene.root.global_position
		var off := Vector2(at.x - point.x, at.z - point.z).length()
		if off < best_m:
			best = scene.station
			best_m = off
	return best


## The scene station `id` is bound to, or null (tests, previews).
func scene_of(id: int) -> Node3D:
	for scene: Scene in _scenes:
		if scene.station == id:
			return scene.root
	return null


## Every station scene of the level for the mode's CarRepairs, bound or not.
func scene_roots() -> Array[Node3D]:
	var roots: Array[Node3D] = []
	for scene: Scene in _scenes:
		roots.append(scene.root)
	return roots


func _ready() -> void:
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	if model == null or level == null or not is_instance_valid(level):
		return
	if _scenes.is_empty():
		_find_scenes()
	var ids := _station_ids()
	if ids != _bound_ids:
		_bind(ids)
	var now := _now(delta)
	for scene: Scene in _scenes:
		if is_instance_valid(scene.root):
			_drive(scene, now)


## The estimated host tick as a float: the last tick read plus the frames since, under one tick.
func _now(delta: float) -> float:
	var tick := 0
	if host_tick.is_valid():
		tick = host_tick.call() as int
	elif model.host_tick_now.is_valid():
		tick = model.host_tick_now.call() as int
	if tick != _tick:
		_tick = tick
		_since_tick = 0.0
	else:
		_since_tick += delta
	return float(tick) + minf(_since_tick * float(Ticks.RATE), 0.999)


## The level's scenes: each use spot in a CarRepair kind's group, its parent the scene's root.
func _find_scenes() -> void:
	for type: CarRepair in CarRepairUse.types_of(mode):
		for kind: StationKind in type.station_kinds():
			if kind == null:
				continue
			var role := CarRepairUse.role_of(type, kind.id)
			for node: Node in get_tree().get_nodes_in_group(StringName("spawn_" + kind.spawn_tag)):
				var spot := node as Node3D
				var root := spot.get_parent() as Node3D if spot != null else null
				if root == null or not level.is_ancestor_of(spot):
					continue
				var scene := Scene.new()
				scene.root = root
				scene.spot = spot
				scene.type = type
				scene.kind = kind
				scene.role = role
				match role:
					CarRepairUse.Role.CAR:
						_find_lift(scene)
					CarRepairUse.Role.PANEL:
						scene.sight = _wrap(root, spot, "Light")
						_show(scene.part("Light"), false)
					CarRepairUse.Role.PICTURE:
						scene.sight = _wrap(root, spot, "Picture")
						_show(scene.part("Picture"), false)
				_scenes.append(scene)


## The car's `Lift` and its rise: from its rest to the hull's underside at the clearance.
func _find_lift(scene: Scene) -> void:
	scene.lift = scene.root.get_node_or_null(^"Lift") as Node3D
	if scene.lift == null:
		push_warning("CarRepairViews: %s has no Lift" % scene.root.name)
		return
	scene.lift_rest_y = scene.lift.position.y
	var lowest := INF
	for child: Node in scene.lift.get_children():
		var shape := child as CollisionShape3D
		if shape == null or not (shape.shape is BoxShape3D):
			continue
		var box := shape.shape as BoxShape3D
		lowest = minf(lowest, shape.position.y - box.size.y / 2.0)
	if lowest == INF:
		push_warning("CarRepairViews: %s's Lift has no box" % scene.root.name)
		lowest = 0.0
	var underside := scene.lift_rest_y + lowest - scene.spot.position.y
	scene.rise_m = maxf(0.0, scene.type.clearance_m - underside)


## The scene's wrapper, made once, holding its part `path`.
func _wrap(root: Node3D, spot: Node3D, path: String) -> StationViews.StationSight:
	var sight := root.get_node_or_null(WRAPPER) as StationViews.StationSight
	if sight != null:
		return sight
	sight = StationViews.StationSight.new()
	sight.name = WRAPPER
	sight.spot = spot
	sight.add_to_group(SightHider.GROUP)
	root.add_child(sight)
	var part := root.get_node_or_null(path) as Node3D
	if part != null:
		part.reparent(sight, true)
	return sight


func _station_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in model.stations:
		if CarRepairUse.type_of(mode, model.stations[id].kind) != null:
			ids.append(id)
	ids.sort()
	return ids


## Binds each placed CarRepair station to the nearest free scene of its kind within tolerance.
func _bind(ids: Array[int]) -> void:
	_bound_ids = ids
	for scene: Scene in _scenes:
		scene.station = -1
	for id: int in ids:
		var station := model.stations[id]
		var best: Scene = null
		var best_m := StationViews.BIND_TOLERANCE_M
		for scene: Scene in _scenes:
			if scene.station >= 0 or not is_instance_valid(scene.root):
				continue
			if scene.kind.id != station.kind:
				continue
			var off := scene.spot.global_position.distance_to(station.position)
			if off <= best_m:
				best = scene
				best_m = off
		if best != null:
			best.station = id


func _drive(scene: Scene, now: float) -> void:
	match scene.role:
		CarRepairUse.Role.CAR:
			_drive_lift(scene, now)
		CarRepairUse.Role.PANEL:
			var panel: ClientModel.Station = model.stations.get(scene.station)
			_show(scene.part("Light"), panel != null and panel.up)
		CarRepairUse.Role.PICTURE:
			_paint_picture(scene)


func _drive_lift(scene: Scene, now: float) -> void:
	if scene.lift == null:
		return
	var fraction := 0.0
	if scene.station >= 0:
		var panel := CarRepairUse.station_of(model, scene.type, CarRepairUse.Role.PANEL)
		fraction = CarRepairUse.lift_fraction(
			panel, now, scene.type.rise_ticks(), Ticks.from_seconds(CarRepairUse.DROP_SECONDS)
		)
	var y := scene.lift_rest_y + fraction * scene.rise_m
	if not is_equal_approx(scene.lift.position.y, y):
		scene.lift.position.y = y


func _paint_picture(scene: Scene) -> void:
	var quad := scene.part("Picture") as MeshInstance3D
	if quad == null:
		return
	var station: ClientModel.Station = model.stations.get(scene.station)
	var part := station.part if station != null else &""
	if part == &"":
		quad.visible = false
		return
	var look := _look_of(scene.type, part)
	if quad.material_override != look:
		quad.material_override = look
	quad.visible = true


## The material of the plate on `part`'s bin when that bin's scene is bound; else a fallback.
func _look_of(type: CarRepair, part: StringName) -> Material:
	var index := -1
	for i in type.parts.size():
		if type.parts[i] != null and type.parts[i].id == part:
			index = i
	var bin := type.bin_of(type.parts[index]) if index >= 0 else null
	if bin != null:
		for scene: Scene in _scenes:
			if scene.station < 0 or scene.kind != bin or not is_instance_valid(scene.root):
				continue
			var plate := scene.root.get_node_or_null(^"Picture") as MeshInstance3D
			if plate == null:
				continue
			var look := plate.get_active_material(0)
			if look != null:
				return look
	var fallback := StandardMaterial3D.new()
	fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fallback.albedo_color = FALLBACK[maxi(index, 0) % FALLBACK.size()]
	return fallback


func _show(node: Node3D, shown: bool) -> void:
	if node != null:
		node.visible = shown
