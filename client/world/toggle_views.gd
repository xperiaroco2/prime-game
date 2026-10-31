class_name ToggleViews
extends Node3D
## The world toggles' parts in the level, driven from the own ClientModel (#1295, ARCHITECTURE
## §4.7.61): the client's side of LevelWorld's toggles, read from the level by the same names
## (StationKind's TOGGLE_ constants). A StaticBody3D in group `toggle_<key>` with the int
## metadata `toggle_index` is a part of toggle (key, index); the toggle is on while its stations
## are (SwitchChanged). A station's index is its ordinal among the model's stations of its kind in
## id order, which is the marker order the host gave it (PlaceToggles, StationState.index).
##
## While its toggle is on, a collider (no child Marker3D `OnPose`) is gone, as on the host: it
## leaves every collision layer, so the client's own rays on layer 1 (SightHider, Muffle's voice
## occlusion) and its player pass through it, and it is hidden with its child meshes (an open
## manhole cover is not drawn shut); a mover stands at its OnPose (the scene pose times the OnPose's
## transform, LevelWorld's pose), its layers kept, its child meshes moving with it. It jumps there:
## a swing's time would be a look nobody chose. Off, or once the model, the mode or the level goes,
## each part stands as the scene put it again.

var model: ClientModel:
	set(value):
		model = value
		if value == null:
			clear()
## The client's own copy of the mode: its toggle kinds (Stations.toggle_kinds).
var mode: GameMode
## The level now (Game's), or null; the old level's parts stand as their scene put them again.
var level: Node:
	set(value):
		clear()
		level = value

var _searched := false
var _parts: Array[Part] = []


## A toggle part of the level and how its scene put it.
class Part:
	extends RefCounted
	var node: StaticBody3D
	var key: StringName
	var index: int
	var layer: int
	var visible: bool
	var rest: Transform3D
	var mover := false
	var on_pose: Transform3D
	var on := false


func _process(_delta: float) -> void:
	if model == null or mode == null or level == null:
		return
	if not _searched:
		_searched = true
		_search(level)
	if _parts.is_empty():
		return
	var open := open_toggles(model, mode)
	for part: Part in _parts:
		_stand(part, open.has(_name_of(part.key, part.index)))


## Every part back as its scene put it, and the level searched again on the next frame.
func clear() -> void:
	for part: Part in _parts:
		_stand(part, false)
	_parts.clear()
	_searched = false


## How many toggle parts the level now has (0 before the first frame with a model).
func part_count() -> int:
	return _parts.size()


## The toggles that are on in `model`, as names `<key>:<index>`: a station of a toggle kind with a
## key that is on, its index its ordinal among its kind's stations in id order.
static func open_toggles(of: ClientModel, game_mode: GameMode) -> Dictionary[String, bool]:
	var keys: Dictionary[StringName, StringName] = {}
	for kind: StationKind in Stations.toggle_kinds(game_mode):
		if not String(kind.toggle_key).is_empty():
			keys[kind.id] = kind.toggle_key
	var open: Dictionary[String, bool] = {}
	if keys.is_empty():
		return open
	var ids := of.stations.keys()
	ids.sort()
	var count: Dictionary[StringName, int] = {}
	for id: int in ids:
		var station := of.stations[id]
		if not keys.has(station.kind):
			continue
		var index := count.get(station.kind, 0) as int
		count[station.kind] = index + 1
		if station.on:
			open[_name_of(keys[station.kind], index)] = true
	return open


static func _name_of(key: StringName, index: int) -> String:
	return "%s:%d" % [key, index]


func _search(node: Node) -> void:
	var body := node as StaticBody3D
	if body != null:
		_add_part(body)
	for child: Node in node.get_children():
		_search(child)


func _add_part(body: StaticBody3D) -> void:
	var key := &""
	for group: StringName in body.get_groups():
		if String(group).begins_with(StationKind.TOGGLE_GROUP_PREFIX):
			key = StringName(String(group).trim_prefix(StationKind.TOGGLE_GROUP_PREFIX))
	var index: Variant = body.get_meta(StationKind.TOGGLE_INDEX_META, null)
	# The host refuses a level whose part has no int index (LevelWorld): nothing to bind here.
	if String(key).is_empty() or not index is int:
		return
	var part := Part.new()
	part.node = body
	part.key = key
	part.index = index as int
	part.layer = body.collision_layer
	part.visible = body.visible
	part.rest = body.transform
	var on_pose := body.get_node_or_null(StationKind.ON_POSE) as Marker3D
	if on_pose != null:
		part.mover = true
		part.on_pose = on_pose.transform
	_parts.append(part)


func _stand(part: Part, on: bool) -> void:
	if part.on == on or not is_instance_valid(part.node):
		return
	part.on = on
	if part.mover:
		part.node.transform = part.rest * part.on_pose if on else part.rest
	else:
		part.node.collision_layer = 0 if on else part.layer
		part.node.visible = part.visible and not on
