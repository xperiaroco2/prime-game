class_name CircleViews
extends Node3D
## The stations of the own ClientModel in 3D (ARCHITECTURE §4.7, M4-8; the M4 ADR's D7 (a), D10
## (b)): each delivery circle a translucent cylinder of its station kind's radius and height (the
## client's own copy of the mode) in StationPlaced's colour, dimmed once PackageDelivered names it.
## A station kind the mode does not name gets a cylinder of the fallback size. A zone (a ZoneTask's
## station kind) is ZoneViews', not drawn here.
##
## Nothing here draws through walls (the M4 ADR's §3 item 5): no marker over a circle, since a
## carried item says where it goes by what it is (Delivery by meaning, DD4 (a), D3a).

## Greybox looks, placeholders until the art pass.
const ALPHA := 0.35
const DONE_ALPHA := 0.1
const DONE_DIM := 0.4
const FALLBACK_RADIUS := 1.0
const FALLBACK_HEIGHT := 0.2

var model: ClientModel
## The client's own copy of the mode: the station kinds' sizes.
var mode: GameMode

var _views: Dictionary[int, MeshInstance3D] = {}
var _done: Dictionary[int, bool] = {}


## The cylinder of station `id`, or null.
func view_of(id: int) -> MeshInstance3D:
	return _views.get(id)


func clear() -> void:
	for view: MeshInstance3D in _views.values():
		view.queue_free()
	_views.clear()
	_done.clear()


## The station kind of `kind_id` in the client's own mode: a StationKind some task type holds
## (Delivery's circle), or null.
static func station_kind(game_mode: GameMode, kind_id: StringName) -> StationKind:
	if game_mode == null:
		return null
	for type: TaskType in game_mode.task_types:
		for property: Dictionary in type.get_property_list():
			var value: Variant = type.get(property["name"] as String)
			if value is StationKind and (value as StationKind).id == kind_id:
				return value as StationKind
	return null


func _process(_delta: float) -> void:
	if model == null:
		return
	for id: int in _views.keys():
		if not model.stations.has(id):
			_views[id].queue_free()
			_views.erase(id)
			_done.erase(id)
	for id: int in model.stations:
		var station := model.stations[id]
		if ZoneViews.zone_task(mode, station.kind) != null:
			continue  # ZoneViews draws the zones.
		var view: MeshInstance3D = _views.get(id)
		if view == null:
			view = _make(id, station)
			_views[id] = view
			add_child(view)
		if _done.get(id, false) != station.done:
			_done[id] = station.done
			_paint(view, station)


func _make(id: int, station: ClientModel.Station) -> MeshInstance3D:
	var kind := station_kind(mode, station.kind)
	var mesh := CylinderMesh.new()
	mesh.top_radius = kind.radius_m if kind != null else FALLBACK_RADIUS
	mesh.bottom_radius = mesh.top_radius
	mesh.height = kind.height_m if kind != null else FALLBACK_HEIGHT
	var view := MeshInstance3D.new()
	view.name = "Circle%d" % id
	view.mesh = mesh
	view.position = station.position + Vector3.UP * mesh.height * 0.5
	_paint(view, station)
	return view


func _paint(view: MeshInstance3D, station: ClientModel.Station) -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var colour := station.colour
	if station.done:
		colour = colour.darkened(DONE_DIM)
	colour.a = DONE_ALPHA if station.done else ALPHA
	material.albedo_color = colour
	view.material_override = material
