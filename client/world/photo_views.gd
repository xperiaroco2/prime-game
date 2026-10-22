class_name PhotoViews
extends Node3D
## The photo task's station scenes in the level, driven from the own ClientModel (#787, photo P8;
## ARCHITECTURE §4.7.58; the photo ADR §3.3, §9). The level holds `levels/stations/camera.tscn`
## and `photo_board.tscn`, each found by its `UseSpot` in the `spawn_<tag>` group of its kind and
## bound to the placed station nearest in 3D within StationViews.BIND_TOLERANCE_M (CookingViews'
## pattern), and the printer's tray, the marker in the group of the photo kind's spawn tag.
##
## - the camera shows its `FramesLeft` label, digits only, while it holds a film (P7's camera
##   state, PhotoUse.frames_left), depth-tested as the scene has it;
## - the film loaded in the camera is drawn at its `FilmSlot` (`drawn_point`), never at the
##   camera's floor point, and is still no item target (`aim_point` names no point for it);
## - a hung photo is drawn upright on the board's `Slots/SlotN` for its slot (ClientModel's
##   `Station.hung`), the picture facing out; past the last slot, stacked in front of it;
## - the photos lying on the tray are spread on a small grid, by item id.
## The items are ItemViews' (at `drawn_point`), each in SightHider's group; the label moves once
## under a StationViews.StationSight wrapper in that group. Sizes are looks, "not a decision".

## Where the film is drawn with no camera scene bound (tests, previews): this high above the
## camera's floor point, as the scene's FilmSlot.
const FILM_SLOT_M := 1.32
## How far in front of the last slot each photo past it stacks.
const STACK_OUT_M := 0.01
## The tray's grid: columns, the step between cards (x, z), how much each later card lies above
## the one before so overlapping cards never fight, and how many lie side by side before the next
## layer starts. Looks, "not a decision".
const TRAY_COLUMNS := 3
const TRAY_STEP := Vector2(0.12, 0.1)
const TRAY_RISE_M := 0.001
const TRAY_LAYER := 9
## A photo resting this close to the tray marker lies on the tray (the print puts it at the marker),
## so a photo on the floor under the printer, or another kind on the tray, is drawn where it lies.
const TRAY_RADIUS_M := 0.05
const PARTS: Array[String] = ["FramesLeft"]
## The card turned upright, its picture (the look's +Y face) facing the board's +Z, the picture's
## top (the look's -Z) up.
const UPRIGHT := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

var model: ClientModel
var mode: GameMode
var level: Node:
	set(value):
		level = value
		_searched = false
		_scenes.clear()
		_trays.clear()
		_bound_ids.clear()

## Whether the level now was searched for scenes: one that holds none is searched once, not on
## every frame (#1198).
var _searched := false
var _scenes: Array[Scene] = []
var _trays: Array[Node3D] = []
var _bound_ids: Array[int] = []


## One camera or board scene.
class Scene:
	extends RefCounted

	var root: Node3D
	var spot: Node3D
	var role := PhotoUse.Role.NONE
	var sight: StationViews.StationSight
	var station := -1
	## What the label shows last: repainted only when it changes.
	var painted := "?"

	func part(path: String) -> Node3D:
		return sight.get_node_or_null(path) as Node3D


## Where item `id` is drawn: the loaded film in its camera's FilmSlot (a Vector3), a hung photo on
## its board slot (a Transform3D), a photo on the tray at its spread point (a Vector3); null for
## anything else (drawn where it lies, or by another view).
func drawn_point(id: int) -> Variant:
	var item: ClientModel.Item = model.items.get(id) if model != null else null
	if item == null or item.holder != ClientModel.NO_HOLDER or item.flying:
		return null
	if item.on_station < 0:
		return _tray_point(id, item)
	var station: ClientModel.Station = model.stations.get(item.on_station)
	if station == null:
		return null
	match PhotoUse.role_of(PhotoUse.type_of(mode, station.kind), station.kind):
		PhotoUse.Role.CAMERA:
			return _film_point(id, item.on_station, station)
		PhotoUse.Role.BOARD:
			return _slot_of(item.on_station, station, id)
	return null


## Where the crosshair aims at item `id`: a hung photo's card, a tray photo's spread point; null
## for anything else, the film loaded in a camera too (drawn, never an item target: P7).
func aim_point(id: int) -> Variant:
	var item: ClientModel.Item = model.items.get(id) if model != null else null
	if item == null:
		return null
	var at: Variant = drawn_point(id)
	if at is Transform3D:
		var hung: Transform3D = at
		return hung * (Vector3.UP * PhotoLooks.size_of(item.kind).y * 0.5)
	if at is Vector3 and item.on_station < 0:
		return ItemView.centre_of(item.kind, at as Vector3)
	return null


## The scene root station `id` is bound to, or null.
func scene_of(id: int) -> Node3D:
	var scene := _scene_of(id)
	return scene.root if scene != null else null


## The camera `id`'s FramesLeft label (under its wrapper once bound), or null.
func frames_label(id: int) -> Label3D:
	var scene := _scene_of(id)
	return scene.part("FramesLeft") as Label3D if scene != null else null


func _process(_delta: float) -> void:
	if model == null or mode == null or level == null or not is_instance_valid(level):
		return
	if not _searched:
		_searched = true
		_find_scenes()
	var ids := _station_ids()
	if ids != _bound_ids:
		_bind(ids)
	for scene: Scene in _scenes:
		if scene.role == PhotoUse.Role.CAMERA and is_instance_valid(scene.root):
			_paint(scene)


## The camera's label: the frames left while it holds a film, hidden otherwise.
func _paint(scene: Scene) -> void:
	var label := scene.part("FramesLeft") as Label3D
	if label == null:
		return
	var loaded := scene.station >= 0 and PhotoUse.is_loaded_camera(model, mode, scene.station)
	var text := str(PhotoUse.frames_left(model, mode, scene.station)) if loaded else ""
	if text == scene.painted:
		return
	scene.painted = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.visible = loaded


## Slot `slot`'s transform on board `board_id` for hung photo `id`; null when it hangs on no slot.
func _slot_of(board_id: int, board: ClientModel.Station, id: int) -> Variant:
	var slot := board.hung.find(id)
	if slot < 0:
		return null
	var scene := _scene_of(board_id)
	var slots := scene.root.get_node_or_null(^"Slots") if scene != null else null
	var count := slots.get_child_count() if slots != null else 0
	if count == 0:
		return null
	var marker := slots.get_child(mini(slot, count - 1)) as Node3D
	var turn := scene.root.global_basis.orthonormalized()
	var out := turn * Vector3.BACK * STACK_OUT_M * maxi(0, slot - count + 1)
	return Transform3D(turn * UPRIGHT, marker.global_position + out)


## The spread point of photo `id` lying on a tray, or null when it lies on none.
func _tray_point(id: int, item: ClientModel.Item) -> Variant:
	if not _is_photo(item.kind):
		return null
	var tray := _tray_under(item.position)
	if tray == null:
		return null
	var rank := 0
	for other_id: int in model.items:
		var other := model.items[other_id]
		if other_id >= id or other.kind != item.kind or not other.rests():
			continue
		if other.on_station < 0 and _tray_under(other.position) == tray:
			rank += 1
	var place := rank % TRAY_LAYER
	var columns := TRAY_COLUMNS
	var rows := ceili(float(TRAY_LAYER) / columns)
	var x := (place % columns - (columns - 1) * 0.5) * TRAY_STEP.x
	var z := (floori(place / float(columns)) - (rows - 1) * 0.5) * TRAY_STEP.y
	var turn := tray.global_basis.orthonormalized()
	return tray.global_position + turn * Vector3(x, 0.0, z) + Vector3.UP * TRAY_RISE_M * rank


func _tray_under(at: Vector3) -> Node3D:
	for tray: Node3D in _trays:
		if not is_instance_valid(tray):
			continue
		var off := tray.global_position - at
		if off.length() <= TRAY_RADIUS_M:
			return tray
	return null


func _find_scenes() -> void:
	for type: PhotoTask in _types():
		for kind: StationKind in [type.camera, type.board]:
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
				scene.role = PhotoUse.role_of(type, kind.id)
				var parts: Array[String] = []
				if scene.role == PhotoUse.Role.CAMERA:
					parts = PARTS
				scene.sight = _wrap(root, spot, parts)
				_scenes.append(scene)
		if type.photo == null:
			continue
		for node: Node in get_tree().get_nodes_in_group(
			StringName("spawn_" + type.photo.spawn_tag)
		):
			var tray := node as Node3D
			if tray != null and level.is_ancestor_of(tray) and not _trays.has(tray):
				_trays.append(tray)


## The scene's wrapper, made once (StationViews' pattern): a second bind finds the first one's.
func _wrap(root: Node3D, spot: Node3D, parts: Array) -> StationViews.StationSight:
	var sight := root.get_node_or_null(StationViews.WRAPPER) as StationViews.StationSight
	if sight != null:
		return sight
	sight = StationViews.StationSight.new()
	sight.name = StationViews.WRAPPER
	sight.spot = spot
	sight.add_to_group(SightHider.GROUP)
	root.add_child(sight)
	for path: String in parts:
		var part := root.get_node_or_null(path) as Node3D
		if part != null:
			part.reparent(sight, true)
	return sight


func _types() -> Array[PhotoTask]:
	return PhotoTaskClient.types_of(mode)


## Whether `kind` is a photo task's photo kind.
func _is_photo(kind: StringName) -> bool:
	for type: PhotoTask in _types():
		if type.photo != null and type.photo.id == kind:
			return true
	return false


func _station_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in model.stations:
		var kind := model.stations[id].kind
		var role := PhotoUse.role_of(PhotoUse.type_of(mode, kind), kind)
		if role == PhotoUse.Role.CAMERA or role == PhotoUse.Role.BOARD:
			ids.append(id)
	ids.sort()
	return ids


func _bind(ids: Array[int]) -> void:
	_bound_ids = ids
	for scene: Scene in _scenes:
		scene.station = -1
		scene.painted = "?"
	for id: int in ids:
		var station := model.stations[id]
		var role := PhotoUse.role_of(PhotoUse.type_of(mode, station.kind), station.kind)
		var best: Scene = null
		var best_m := StationViews.BIND_TOLERANCE_M
		for scene: Scene in _scenes:
			if scene.station >= 0 or scene.role != role or not is_instance_valid(scene.root):
				continue
			var off := scene.spot.global_position.distance_to(station.position)
			if off <= best_m:
				best = scene
				best_m = off
		if best != null:
			best.station = id


func _scene_of(id: int) -> Scene:
	for scene: Scene in _scenes:
		if scene.station == id and is_instance_valid(scene.root):
			return scene
	return null


## The loaded film `id` in camera `camera_id`: at its scene's FilmSlot, else FILM_SLOT_M above
## the camera's floor point; null when the camera holds another film.
func _film_point(id: int, camera_id: int, station: ClientModel.Station) -> Variant:
	if station.film != id:
		return null
	var scene := _scene_of(camera_id)
	var slot := scene.root.get_node_or_null(^"FilmSlot") as Node3D if scene != null else null
	if slot != null:
		return slot.global_position
	return station.position + Vector3.UP * FILM_SLOT_M
