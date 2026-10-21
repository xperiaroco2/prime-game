class_name StationViews
extends Node3D
## The Generator's station scenes in the level, driven from the own ClientModel (#801, ARCHITECTURE
## §4.7.54; the Generator ADR's GD4, GE11, GE14; the level-piece ADR's "Station scenes"). The level
## holds a scene per device (`levels/stations/switch.tscn`, `generator.tscn`), found by its
## `UseSpot` in the `spawn_<tag>` group of its kind; a placed station binds to the scene of its kind
## whose use spot is nearest in 3D, within BIND_TOLERANCE_M (the host snaps the marker there).
##
## While the Generator is dealt (its generator station placed):
## - a bound switch shows `Active`, its `On` or `Off` by SwitchChanged; a switch scene no station
##   binds is a fixed one (GE14): `Fixed` shown, `Active` hidden, and no station to aim at;
## - the generator lights `Bars/Bar1` up from the fixed switches' count plus the switches on, and
##   `Glow` once all are lit (GD4); `Button` moves in by PRESS_DEPTH_M for PRESS_SECONDS at each
##   ButtonPressed (`presses`), a press before the bind replaying nothing.
## Not dealt: every scene keeps its default look. Everything is the level's own depth-tested
## meshes, drawn on no screen. The driven parts (never `Fixed`, which tells nothing a fixed switch
## does not) are moved once per scene under a StationSight wrapper in SightHider's group, as
## ZoneViews' FillSight (render checklist item 3): nothing here sets the wrapper's `visible`.

## How far a station's floor point may lie from its scene's use spot, in metres.
const BIND_TOLERANCE_M := 0.5
## The wrapper's sight point above the use spot: the panel's height, since a floor-level point is
## hidden by any clutter (a look, "not a decision").
const SIGHT_HEIGHT_M := 1.0
## The button's press, a look ("not a decision").
const PRESS_DEPTH_M := 0.02
const PRESS_SECONDS := 0.15
const WRAPPER := "StationSight"
## The scenes' named parts (the level-piece ADR's "Station scenes").
const SWITCH_PARTS: Array[String] = ["Active"]
const GENERATOR_PARTS: Array[String] = ["Button", "Bars", "Glow"]

var model: ClientModel
## The client's own copy of the mode: the Generator's kinds and its switch count.
var mode: GameMode
## The level now (Game's), or null; a new one is searched for scenes again.
var level: Node:
	set(value):
		level = value
		_searched = false
		_scenes.clear()
		_bound_ids.clear()

## Whether the level now was searched for scenes: one that holds none is searched once, not on
## every frame (#1198).
var _searched := false
var _scenes: Array[Scene] = []
## The station ids of the last bind, sorted: a new deal binds again.
var _bound_ids: Array[int] = []


## The holder of a scene's driven parts: SightHider's group sets its `visible`.
class StationSight:
	extends Node3D

	var spot: Node3D

	func sight_point() -> Vector3:
		var base := spot.global_position if spot != null else global_position
		return base + Vector3.UP * SIGHT_HEIGHT_M


## One station scene of the level.
class Scene:
	extends RefCounted

	var root: Node3D
	var spot: Node3D
	var type: Generator
	var is_generator := false
	var sight: StationSight
	var station := -1
	var presses := 0
	var press_left := 0.0
	var button_rest := Vector3.ZERO

	## A driven part, looked up under the wrapper only (it moved there at the first bind).
	func part(path: String) -> Node3D:
		return sight.get_node_or_null(path) as Node3D


## The station whose scene `body` collides for (its `Collision`), while it is bound; -1 otherwise.
func station_of_body(body: Object) -> int:
	for scene: Scene in _scenes:
		if scene.station >= 0 and body == scene.root.get_node_or_null(^"Collision"):
			return scene.station
	return -1


## The scene station `id` is bound to, or null (tests, previews).
func scene_of(id: int) -> Node3D:
	for scene: Scene in _scenes:
		if scene.station == id:
			return scene.root
	return null


## Every station scene of the level for the mode's Generators, bound or not.
func scene_roots() -> Array[Node3D]:
	var roots: Array[Node3D] = []
	for scene: Scene in _scenes:
		roots.append(scene.root)
	return roots


func _process(delta: float) -> void:
	if model == null or level == null or not is_instance_valid(level):
		return
	if not _searched and mode != null:
		_searched = true
		_find_scenes()
	var ids := _station_ids()
	if ids != _bound_ids:
		_bind(ids)
	for scene: Scene in _scenes:
		if is_instance_valid(scene.root):
			_drive(scene, delta)


## The level's scenes: each use spot in a Generator kind's group, its parent the scene's root.
func _find_scenes() -> void:
	for type: Generator in StationUse.generators_of(mode):
		for kind: StationKind in [type.generator, type.switch]:
			if kind == null:
				continue
			for node: Node in get_tree().get_nodes_in_group(StringName("spawn_" + kind.spawn_tag)):
				var spot := node as Node3D
				var root := spot.get_parent() as Node3D if spot != null else null
				if root == null or not level.is_ancestor_of(spot):
					continue
				var scene := Scene.new()
				scene.root = root
				scene.spot = spot
				scene.type = type
				scene.is_generator = kind == type.generator
				scene.sight = _wrap(
					root, spot, GENERATOR_PARTS if scene.is_generator else SWITCH_PARTS
				)
				var button := scene.part("Button")
				scene.button_rest = button.position if button != null else Vector3.ZERO
				_scenes.append(scene)
				if scene.is_generator:
					_check_bars(scene)


## The scene's wrapper, made once: a second bind finds the one the first made.
func _wrap(root: Node3D, spot: Node3D, parts: Array[String]) -> StationSight:
	var sight := root.get_node_or_null(WRAPPER) as StationSight
	if sight != null:
		return sight
	sight = StationSight.new()
	sight.name = WRAPPER
	sight.spot = spot
	sight.add_to_group(SightHider.GROUP)
	root.add_child(sight)
	for path: String in parts:
		var part := root.get_node_or_null(path) as Node3D
		if part != null:
			part.reparent(sight, true)
	return sight


## The generator's bars against its type's switch count (GE10 draws four).
func _check_bars(scene: Scene) -> void:
	var bars := scene.part("Bars")
	var count := 0
	if bars != null:
		for child: Node in bars.get_children():
			if child.name.begins_with("Bar"):
				count += 1
	if count != scene.type.switches:
		push_warning(
			(
				"StationViews: %s has %d bars for %d switches"
				% [scene.root.name, count, scene.type.switches]
			)
		)


func _station_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in model.stations:
		if StationUse.generator_of(mode, model.stations[id].kind) != null:
			ids.append(id)
	ids.sort()
	return ids


## Binds each placed Generator station to the nearest free scene of its kind within tolerance.
func _bind(ids: Array[int]) -> void:
	_bound_ids = ids
	for scene: Scene in _scenes:
		scene.station = -1
	for id: int in ids:
		var station := model.stations[id]
		var best: Scene = null
		var best_m := BIND_TOLERANCE_M
		for scene: Scene in _scenes:
			if scene.station >= 0 or not is_instance_valid(scene.root):
				continue
			var kind := scene.type.generator if scene.is_generator else scene.type.switch
			if kind.id != station.kind:
				continue
			var off := scene.spot.global_position.distance_to(station.position)
			if off <= best_m:
				best = scene
				best_m = off
		if best != null:
			best.station = id
			best.presses = station.presses
			best.press_left = 0.0


func _drive(scene: Scene, delta: float) -> void:
	var generator_id := StationUse.generator_station(model, scene.type)
	var dealt := generator_id >= 0
	if not scene.is_generator:
		var station: ClientModel.Station = model.stations.get(scene.station)
		var active := not dealt or station != null
		var on := station != null and station.on
		_show(scene.root.get_node_or_null(^"Fixed") as Node3D, not active)
		_show(scene.part("Active"), active)
		_show(scene.part("Active/On"), on)
		_show(scene.part("Active/Off"), not on)
		return
	var lit := _lit(scene.type) if dealt else 0
	for i in scene.type.switches:
		_show(scene.part("Bars/Bar%d" % (i + 1)), i < lit)
	_show(scene.part("Glow"), dealt and lit >= scene.type.switches)
	_press(scene, model.stations.get(scene.station) as ClientModel.Station, delta)


## The bars lit: the fixed switches' (no station) plus the placed switches on.
func _lit(type: Generator) -> int:
	var placed := 0
	var on := 0
	for id: int in model.stations:
		var station := model.stations[id]
		if type.switch != null and station.kind == type.switch.id:
			placed += 1
			if station.on:
				on += 1
	return maxi(0, type.switches - placed) + on


func _press(scene: Scene, station: ClientModel.Station, delta: float) -> void:
	var button := scene.part("Button")
	if button == null:
		return
	if station != null and station.presses > scene.presses:
		scene.presses = station.presses
		scene.press_left = PRESS_SECONDS
	elif scene.press_left > 0.0:
		scene.press_left -= delta
	var pressed := scene.press_left > 0.0
	button.position = (
		scene.button_rest + (Vector3.BACK * -PRESS_DEPTH_M if pressed else Vector3.ZERO)
	)


func _show(node: Node3D, shown: bool) -> void:
	if node != null:
		node.visible = shown
