class_name ZoneViews
extends Node3D
## The zones of the own ClientModel in 3D (ARCHITECTURE §4.7; the zone task ADR's ZD11 (b) and
## ZE8, #650): each zone a look of its own on the floor, apart from the delivery circles'
## cylinders: a ring at the zone's radius over a faint disc, in StationPlaced's colour, and a fill,
## a disc that grows from the centre to the ring as the zone's time runs (its radius the share of
## the time counted). A done zone is full and dimmed.
##
## A station is a zone when its kind is a ZoneTask's zone in the client's own copy of the mode;
## CircleViews leaves those out. The fill is fill(): a pure function of the station as the model
## folded it from the host's ZoneProgress and of the estimated host tick (`host_tick`, AvatarViews'
## host_tick() in the game), extrapolated between two events while the zone counts and capped at
## its needed ticks. Nothing is predicted: the fill starts, stops and is done only on ZoneProgress.
##
## The M4 render checklist (the M4 ADR's §3): every part is depth-tested (no `no_depth_test`;
## items 5 and 10), so the fill, which tells that a living player stands at that place, never shows
## through walls; there is no marker, label or HUD line for zones (ZD11), and no sound. The fill
## also tells who stands there, as an avatar does, so it sits under a FillSight wrapper in
## SightHider's group (item 3): the downed camera shows it only where the body's eye could see the
## zone's centre. The disc and the ring are the level's fixed, public place and stay drawn.

## Greybox looks, placeholders until the art pass.
const DISC_ALPHA := 0.15
const FILL_ALPHA := 0.55
const RING_ALPHA := 0.9
const DONE_ALPHA := 0.25
const DONE_DIM := 0.4
## The ring's width and the discs' thickness, in metres.
const RING_WIDTH := 0.12
const DISC_THICKNESS := 0.01
## How far above the floor the disc, the fill and the ring sit, so they do not fight the floor
## (or each other) for depth.
const DISC_LIFT := 0.01
const FILL_LIFT := 0.02
const RING_LIFT := 0.03
## The ring is a torus squashed to this share of its height, so it lies flat over the fill.
const RING_FLAT := 0.1
## What a sight point sits above the zone's floor, so the floor under it does not block the ray.
const SIGHT_LIFT := 0.1
## The sort offset of each part over the one under it (VisualInstance3D.sorting_offset): the disc,
## the fill and the ring draw in that order among themselves but sort by camera distance against
## everything else (render_priority would put them after every other translucent object).
const SORT_STEP := 0.02
## The fill's smallest drawn scale: a basis of scale 0 is singular.
const MIN_SCALE := 0.001
const FALLBACK_RADIUS := 1.0

var model: ClientModel
## The client's own copy of the mode: which station kinds are zones, and their sizes.
var mode: GameMode
## The estimated host tick now (AvatarViews.host_tick); unset: the newest snapshot's tick.
var host_tick := Callable()

var _views: Dictionary[int, Node3D] = {}
var _done: Dictionary[int, bool] = {}


## The holder of a zone's fill: SightHider's group sets its `visible` (nothing else does); the fill
## inside keeps its own, for empty.
class FillSight:
	extends Node3D

	func sight_point() -> Vector3:
		return global_position + Vector3.UP * SIGHT_LIFT


## The ZoneTask of `game_mode` whose zone is the station kind `kind_id`, or null: such a station
## is a zone.
static func zone_task(game_mode: GameMode, kind_id: StringName) -> ZoneTask:
	if game_mode == null:
		return null
	for type: TaskType in game_mode.task_types:
		var zone_type := type as ZoneTask
		if zone_type != null and zone_type.zone != null and zone_type.zone.id == kind_id:
			return zone_type
	return null


## The ticks `station` has counted at host tick `now`, as far as the client can tell: its last
## ZoneProgress's ticks, plus the host ticks since that event's tick while it counts, capped at
## its needed ticks. `now` -1 (no estimate yet), or behind the event, adds nothing.
static func ticks_at(station: ClientModel.Station, now: int) -> int:
	if station.done:
		return station.needed
	var ticks := station.ticks
	if station.counting and station.progress_tick >= 0 and now > station.progress_tick:
		ticks += now - station.progress_tick
	return mini(ticks, station.needed) if station.needed > 0 else ticks


## The share of its time `station` has counted at host tick `now`, 0 to 1: the fill's radius as a
## share of the zone's. A done zone is full; one with no ZoneProgress yet is empty.
static func fill(station: ClientModel.Station, now: int) -> float:
	if station.done:
		return 1.0
	if station.needed <= 0:
		return 0.0
	return clampf(float(ticks_at(station, now)) / station.needed, 0.0, 1.0)


## The view of zone `id` (its children: Disc, Ring and FillSight, which holds Fill), or null.
func view_of(id: int) -> Node3D:
	return _views.get(id)


## How many zones are drawn.
func count() -> int:
	return _views.size()


func clear() -> void:
	for view: Node3D in _views.values():
		view.queue_free()
	_views.clear()
	_done.clear()


func _process(_delta: float) -> void:
	if model == null:
		return
	for id: int in _views.keys():
		var gone: ClientModel.Station = model.stations.get(id)
		if gone == null or zone_task(mode, gone.kind) == null:
			_views[id].queue_free()
			_views.erase(id)
			_done.erase(id)
	var now := _now()
	for id: int in model.stations:
		var station := model.stations[id]
		var task := zone_task(mode, station.kind)
		if task == null:
			continue
		var view: Node3D = _views.get(id)
		if view == null:
			view = _make(id, station, task.zone)
			_views[id] = view
			add_child(view)
		if _done.get(id, false) != station.done:
			_done[id] = station.done
			_paint(view, station)
		_show_fill(_part(view, ^"FillSight/Fill"), fill(station, now))


func _now() -> int:
	if host_tick.is_valid():
		return host_tick.call() as int
	return model.snapshot_tick


func _make(id: int, station: ClientModel.Station, kind: StationKind) -> Node3D:
	var radius := kind.radius_m if kind.radius_m > 0.0 else FALLBACK_RADIUS
	var view := Node3D.new()
	view.name = "Zone%d" % id
	view.position = station.position
	view.add_child(_disc("Disc", radius, DISC_LIFT, 0.0))
	var sight := FillSight.new()
	sight.name = "FillSight"
	sight.add_child(_disc("Fill", radius, FILL_LIFT, SORT_STEP))
	sight.add_to_group(SightHider.GROUP)
	view.add_child(sight)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(radius - RING_WIDTH, 0.0)
	torus.outer_radius = radius
	ring.mesh = torus
	ring.scale = Vector3(1.0, RING_FLAT, 1.0)
	# Its lowest point (the squashed tube's radius under its centre) rests on the fill's top.
	var tube := (torus.outer_radius - torus.inner_radius) * 0.5
	ring.position = Vector3.UP * (RING_LIFT + tube * RING_FLAT)
	ring.sorting_offset = SORT_STEP * 2.0
	view.add_child(ring)
	_paint(view, station)
	return view


func _disc(disc_name: String, radius: float, lift: float, sorting: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = DISC_THICKNESS
	var disc := MeshInstance3D.new()
	disc.name = disc_name
	disc.mesh = mesh
	disc.position = Vector3.UP * (lift + DISC_THICKNESS * 0.5)
	disc.sorting_offset = sorting
	return disc


## Colours the disc, the fill and the ring: dimmed when done. Each is depth-tested; their order
## among themselves is their sorting_offset.
func _paint(view: Node3D, station: ClientModel.Station) -> void:
	var colour := station.colour.darkened(DONE_DIM) if station.done else station.colour
	var fill_alpha := DONE_ALPHA if station.done else FILL_ALPHA
	var ring_alpha := DONE_ALPHA if station.done else RING_ALPHA
	_part(view, ^"Disc").material_override = _material(colour, DISC_ALPHA)
	_part(view, ^"FillSight/Fill").material_override = _material(colour, fill_alpha)
	_part(view, ^"Ring").material_override = _material(colour, ring_alpha)


static func _part(view: Node3D, path: NodePath) -> MeshInstance3D:
	return view.get_node(path) as MeshInstance3D


static func _material(colour: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tint := colour
	tint.a = alpha
	material.albedo_color = tint
	return material


## The fill at `share` of the zone's radius; hidden while empty.
func _show_fill(fill_view: MeshInstance3D, share: float) -> void:
	fill_view.visible = share > 0.0
	var across := maxf(share, MIN_SCALE)
	fill_view.scale = Vector3(across, 1.0, across)
