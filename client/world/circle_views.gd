class_name CircleViews
extends Node3D
## The stations of the own ClientModel in 3D (ARCHITECTURE §4.7, M4-8; the M4 ADR's D7 (a), D10
## (b)): each delivery circle a translucent cylinder of its station kind's radius and height (the
## client's own copy of the mode) in StationPlaced's colour, dimmed once PackageDelivered names it.
## A station kind the mode does not name gets a cylinder of the fallback size.
##
## The destination marker: while the own player carries a package (ItemViews.destination_item), a
## marker floats over its circle and is drawn through walls (`no_depth_test`). It is the one
## exception to the M4 ADR's §3 item 5, since circles are fixed, public places (D10 (b)); no
## other marker or label of the client may use it.

## Greybox looks, placeholders until the art pass.
const ALPHA := 0.35
const DONE_ALPHA := 0.1
const DONE_DIM := 0.4
const FALLBACK_RADIUS := 1.0
const FALLBACK_HEIGHT := 0.2
## How far over the circle's top the marker floats, and its size, in metres.
const MARKER_ABOVE := 2.0
const MARKER_SIZE := 0.35

var model: ClientModel
## The client's own copy of the mode: the station kinds' sizes.
var mode: GameMode

var _views: Dictionary[int, MeshInstance3D] = {}
var _done: Dictionary[int, bool] = {}
var _marker := MeshInstance3D.new()
var _marked := -1


func _init() -> void:
	_marker.name = "DestinationMarker"
	var mesh := PrismMesh.new()
	mesh.size = Vector3.ONE * MARKER_SIZE
	_marker.mesh = mesh
	# Upside down: it points at the circle.
	_marker.rotation = Vector3(PI, 0.0, 0.0)
	_marker.visible = false
	add_child(_marker)


## The cylinder of station `id`, or null.
func view_of(id: int) -> MeshInstance3D:
	return _views.get(id)


## The destination marker; hidden when the own player carries no package.
func marker() -> MeshInstance3D:
	return _marker


## The station the marker is over, or -1.
func marked() -> int:
	return _marked if _marker.visible else -1


func clear() -> void:
	for view: MeshInstance3D in _views.values():
		view.queue_free()
	_views.clear()
	_done.clear()
	_marker.visible = false


## The station kind of `kind_id` in the client's own mode: a StationKind some task type holds
## (Delivery's circle), or null.
static func station_kind(game_mode: GameMode, kind_id: StringName) -> StationKind:
	if game_mode == null:
		return null
	for type: TaskType in game_mode.task_types:
		for property: Dictionary in type.get_property_list():
			var value: Variant = type.get(property["name"] as String)
			var kind := value as StationKind
			if kind != null and kind.id == kind_id:
				return kind
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
		var view: MeshInstance3D = _views.get(id)
		if view == null:
			view = _make(id, station)
			_views[id] = view
			add_child(view)
		if _done.get(id, false) != station.done:
			_done[id] = station.done
			_paint(view, station)
	_mark()


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
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var colour := station.colour
	if station.done:
		colour = colour.darkened(DONE_DIM)
	colour.a = DONE_ALPHA if station.done else ALPHA
	material.albedo_color = colour
	view.material_override = material


## The marker over the own package's circle, in its colour, through walls.
func _mark() -> void:
	var package: ClientModel.Item = model.items.get(ItemViews.destination_item(model))
	var station: ClientModel.Station = (
		model.stations.get(package.station) if package != null else null
	)
	if station == null:
		_marker.visible = false
		return
	var top := station.position.y
	var view: MeshInstance3D = _views.get(package.station)
	if view != null:
		top = view.position.y + (view.mesh as CylinderMesh).height * 0.5
	_marker.position = Vector3(station.position.x, top + MARKER_ABOVE, station.position.z)
	if _marked != package.station or not _marker.visible:
		_marked = package.station
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.albedo_color = station.colour
		_marker.material_override = material
	_marker.visible = true
