class_name CircleViews
extends Node3D
## The stations of the own ClientModel in 3D (ARCHITECTURE §4.7, M4-8; the M4 ADR's D7 (a), D10
## (b)): each delivery circle a translucent cylinder of its station kind's radius and height (the
## client's own copy of the mode) in StationPlaced's colour, dimmed once PackageDelivered names it.
## A station kind the mode does not name gets a cylinder of the fallback size. A zone (a ZoneTask's
## station kind) is ZoneViews', not drawn here, and so is every other task type's station (`draws`;
## a Generator's generator and switch are the level's station scenes, StationViews, #801).
##
## A drop-off of Delivery by meaning (DE11 of the delivery-by-meaning ADR, #830), told from a circle
## by which of the client's own Delivery types lists its kind (`is_drop_off`): an open tube of its
## kind's radius and height, with no caps, in one neutral colour, never StationPlaced's (white for
## a drop-off, DE5 (b)), dimmed once done: neither a circle's coloured cylinder nor a zone's disc
## and ring.
##
## Nothing here draws through walls (the M4 ADR's §3 item 5): no marker over a circle, since a
## carried item says where it goes by what it is (Delivery by meaning, DD4 (a), D3a).

## Greybox looks, placeholders until the art pass.
const ALPHA := 0.35
const DONE_ALPHA := 0.1
const DONE_DIM := 0.4
const FALLBACK_RADIUS := 1.0
const FALLBACK_HEIGHT := 0.2
## A drop-off's one neutral colour: never a circle palette's or StationPlaced's.
const DROP_OFF_COLOUR := Color(0.8, 0.8, 0.8)

var model: ClientModel
## The client's own copy of the mode: the station kinds' sizes.
var mode: GameMode

var _views: Dictionary[int, MeshInstance3D] = {}
var _done: Dictionary[int, bool] = {}


## The look of station `id` (a circle's cylinder or a drop-off's tube), or null.
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
		if type == null:
			continue
		for kind: StationKind in type.station_kinds():
			if kind.id == kind_id:
				return kind
	return null


## Whether `kind_id` is a drop-off of Delivery by meaning (DE11): one of the client's own
## DeliveryByMeaning types lists it among its station kinds. Any other station kind (today's
## Delivery's `circle`) is a circle.
static func is_drop_off(game_mode: GameMode, kind_id: StringName) -> bool:
	for type: DeliveryByMeaning in DeliveryByMeaningClient.types_of(game_mode):
		for kind: StationKind in type.station_kinds():
			if kind.id == kind_id:
				return true
	return false


## Whether a station of `kind_id` is drawn here (#801's G6: only Delivery's circles): a kind of a
## task type whose TaskClient draws it as a circle (Delivery's and Delivery by meaning's, #1260),
## or one no task type of the mode holds (the fallback cylinder). A zone is ZoneViews'; a
## Generator's generator and switch are the level's station scenes (StationViews); every other
## task type's stations are its own view's. A world toggle's kind (#1295) is never drawn: its
## look is the level's own (the bookcase, a cover, the breaker), and a cylinder would mark a
## secret passage.
static func draws(game_mode: GameMode, kind_id: StringName) -> bool:
	if game_mode == null:
		return true
	for kind: StationKind in Stations.toggle_kinds(game_mode):
		if kind.id == kind_id:
			return false
	var held := false
	for type: TaskType in game_mode.task_types:
		if type == null:
			continue
		for kind: StationKind in type.station_kinds():
			if kind.id != kind_id:
				continue
			var client := TaskClients.of(type)
			if client != null and client.draws_circle(kind_id):
				return true
			held = true
	return not held


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
		if not draws(mode, station.kind):
			continue  # Another view's, or none yet.
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
	var drop_off := is_drop_off(mode, station.kind)
	if drop_off:
		# An open tube: no cap hides the floor or the table inside, unlike a circle's cylinder.
		mesh.cap_top = false
		mesh.cap_bottom = false
	var view := MeshInstance3D.new()
	view.name = ("DropOff%d" if drop_off else "Circle%d") % id
	view.mesh = mesh
	view.position = station.position + Vector3.UP * mesh.height * 0.5
	_paint(view, station)
	return view


func _paint(view: MeshInstance3D, station: ClientModel.Station) -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var colour := station.colour
	if is_drop_off(mode, station.kind):
		# Never StationPlaced's colour (white for a drop-off, DE5 (b)); both faces of the tube.
		colour = DROP_OFF_COLOUR
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if station.done:
		colour = colour.darkened(DONE_DIM)
	colour.a = DONE_ALPHA if station.done else ALPHA
	material.albedo_color = colour
	view.material_override = material
