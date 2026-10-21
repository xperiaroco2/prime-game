class_name CookingViews
extends Node3D
## Cooking's station scenes in the level, driven from the own ClientModel (#776, ARCHITECTURE
## §4.7.55; the cooking ADR's §3, CD12 (a), CD14 (i), CE15). The level holds a scene per station
## (`levels/stations/order_board.tscn`, `herb_board.tscn`, `grill.tscn`, `place.tscn`, and five
## beds under one `herb_beds.tscn`), found by its `UseSpot` in the `spawn_<tag>` group of its kind;
## a station binds to its use spot's parent (a bed to its `BedN`, CE15) nearest in 3D within
## StationViews.BIND_TOLERANCE_M, as StationViews binds the Generator's.
##
## - the order board shows `Rows/RowN` for place number N with an order: its number, the bun and
##   the fried patty as pictures, the herb's icon (never the herb, CE9);
## - the herb board shows `Pairs/PairN`: icon N-1 and the herb it means (HerbsDealt's code);
## - the k-th bed (station id order) grows HerbsDealt's k-th bed herb at its `Plant`;
## - a bound place with an order shows its `Plate` and its `Number` (its row on the board);
## - the grill shows its `Ring` filling to fried, then to burnt, extrapolated from GrillLoaded's
##   ticks with `host_tick` (CD14 (i)).
## The items on a plate or the grill are ItemViews' (at `point_of`), outlined there. Everything is
## drawn in the world, depth-tested, on no screen; the driven parts move once per scene under a
## StationViews.StationSight wrapper in SightHider's group. Nothing here keeps who put what.

enum Ring { NONE, FRYING, BURNING, BURNT }

## The ring's segments: its fill is drawn as a share of them.
const RING_SEGMENTS := 24
const RING_RADIUS_M := 0.195
const RING_FRYING := Color(1.0, 0.8, 0.15)
const RING_BURNING := Color(0.9, 0.22, 0.1)
## Where a plate's ingredients stand above the plate's origin, by slot (bun, patty, herb), each on
## the one below as in a plated burger (CookingLooks.BURGER_STACK_M), so the bun never hides the
## patty: looks, "not a decision".
const STACK_M: Array[float] = [
	0.01,
	0.01 + CookingLooks.BUN_TOP_M,
	0.01 + CookingLooks.BUN_TOP_M + CookingLooks.PATTY_TALL_M,
]
## Above the grate's origin, where the patty lies: a look.
const GRATE_TOP_M := 0.02
## Unbound (tests, previews): the plate or grate this high above the station's floor point.
const COUNTER_M := 0.9
## How big a board's or bed's picture is drawn: its look scaled so its largest side is this long
## (a board's pictures fit its rows, 0.3 m apart). Looks, "not a decision".
const BOARD_PICTURE_M := 0.2
const PLANT_M := 0.5
const ICON_PIXEL_M := 0.0025
const PICTURE := "Picture"
const PARTS: Dictionary[CookingUse.Role, Array] = {
	CookingUse.Role.ORDER_BOARD: ["Rows"],
	CookingUse.Role.HERB_BOARD: ["Pairs"],
	CookingUse.Role.BED: ["Plant"],
	CookingUse.Role.PLACE: ["Plate", "Number"],
	CookingUse.Role.GRILL: ["Ring"],
}

static var _ring_materials: Dictionary[bool, StandardMaterial3D] = {}

var model: ClientModel
var mode: GameMode
## The estimated host tick now (AvatarViews.host_tick); unset: the model's host tick.
var host_tick := Callable()
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
var _bound_ids: Array[int] = []


## One station scene (a bed: its `BedN`).
class Scene:
	extends RefCounted

	var root: Node3D
	var spot: Node3D
	var type: Cooking
	var role := CookingUse.Role.NONE
	var sight: StationViews.StationSight
	var station := -1
	## What was painted last: repainted only when it changes.
	var painted := ""

	func part(path: String) -> Node3D:
		return sight.get_node_or_null(path) as Node3D


## The ring's phase for the grill `station` at host tick `now`.
static func ring_phase(station: ClientModel.Station, now: int) -> Ring:
	if station == null or station.grill_item < 0 or station.fried_tick < 0:
		return Ring.NONE
	if now < station.fried_tick:
		return Ring.FRYING
	return Ring.BURNING if now < station.burnt_tick else Ring.BURNT


## The ring's fill, 0 to 1, at host tick `now`: towards fried from the load (`type`'s fried_ticks
## before GrillLoaded's fried tick), then towards burnt; full once burnt, empty with no patty.
static func ring_fill(type: Cooking, station: ClientModel.Station, now: int) -> float:
	match ring_phase(station, now):
		Ring.FRYING:
			var frying := type.fried_ticks() if type != null else 1
			return clampf(1.0 - float(station.fried_tick - now) / maxi(1, frying), 0.0, 1.0)
		Ring.BURNING:
			var span := maxi(1, station.burnt_tick - station.fried_tick)
			return clampf(float(now - station.fried_tick) / span, 0.0, 1.0)
		Ring.BURNT:
			return 1.0
	return 0.0


## Where item `id`, lying on a place or the grill, is drawn: on the plate, stacked by its slot
## (every put is locked on its slot since #1101), or on the grate; null for an item on no cooking
## station. The crosshair aims there (TargetChoice's aim_of); the host's sight check stays on its
## position.
func point_of(id: int) -> Variant:
	var item: ClientModel.Item = model.items.get(id) if model != null else null
	if item == null or item.on_station < 0 or not model.stations.has(item.on_station):
		return null
	var station := model.stations[item.on_station]
	var type := CookingUse.type_of(mode, station.kind)
	var role := CookingUse.role_of(type, station.kind)
	var scene := _scene_of(item.on_station)
	var base := station.position + Vector3.UP * COUNTER_M
	if role == CookingUse.Role.GRILL:
		var grate := scene.root.get_node_or_null(^"Grate") as Node3D if scene != null else null
		base = grate.global_position if grate != null else base
		return base + Vector3.UP * GRATE_TOP_M
	if role != CookingUse.Role.PLACE:
		return null
	var plate := scene.part("Plate") if scene != null else null
	if plate != null:
		base = plate.global_position
	var slot := maxi(0, CookingUse.slot_of(type, item.kind))
	return base + Vector3.UP * STACK_M[slot]


## The station whose scene the ray hit: `body` a bound scene's `Collision`, or the beds' shared
## collider, `shape` the hit shape's index (its `ShapeN` names `BedN`); -1 otherwise.
func station_of_hit(body: Object, shape: int) -> int:
	for scene: Scene in _scenes:
		if scene.station < 0 or not is_instance_valid(scene.root):
			continue
		if scene.role != CookingUse.Role.BED:
			if body == scene.root.get_node_or_null(^"Collision"):
				return scene.station
			continue
		var beds := scene.root.get_parent()
		var collider := beds.get_node_or_null(^"Collision") as CollisionObject3D if beds else null
		if collider == null or body != collider:
			continue
		var owner_id := collider.shape_find_owner(shape)
		var node := collider.shape_owner_get_owner(owner_id) as Node if owner_id >= 0 else null
		var bed_number := String(scene.root.name).trim_prefix("Bed")
		if node != null and String(node.name).trim_prefix("Shape") == bed_number:
			return scene.station
	return -1


## The scene root station `id` is bound to (a bed's `BedN`), or null.
func scene_of(id: int) -> Node3D:
	var scene := _scene_of(id)
	return scene.root if scene != null else null


## Every cooking station scene of the level, bound or not, for the tests.
func scene_roots() -> Array[Node3D]:
	var roots: Array[Node3D] = []
	for scene: Scene in _scenes:
		roots.append(scene.root)
	return roots


func _process(_delta: float) -> void:
	if model == null or level == null or not is_instance_valid(level):
		return
	if not _searched and mode != null:
		_searched = true
		_find_scenes()
	var ids := _station_ids()
	if ids != _bound_ids:
		_bind(ids)
	var now := _now()
	for scene: Scene in _scenes:
		if is_instance_valid(scene.root):
			_drive(scene, now)


func _now() -> int:
	if host_tick.is_valid():
		return host_tick.call() as int
	return model.host_tick_now.call() as int if model.host_tick_now.is_valid() else 0


func _find_scenes() -> void:
	for type: Cooking in CookingUse.types_of(mode):
		for kind: StationKind in [
			type.order_board, type.herb_board, type.grill, type.herb_bed, type.place
		]:
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
				scene.role = CookingUse.role_of(type, kind.id)
				var parts: Array = PARTS.get(scene.role, [])
				scene.sight = _wrap(root, spot, parts)
				_scenes.append(scene)
				if scene.role == CookingUse.Role.GRILL:
					_build_ring(scene)


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


func _station_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in model.stations:
		if CookingUse.type_of(mode, model.stations[id].kind) != null:
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
		var best: Scene = null
		var best_m := StationViews.BIND_TOLERANCE_M
		for scene: Scene in _scenes:
			if scene.station >= 0 or not is_instance_valid(scene.root):
				continue
			if CookingUse.role_of(scene.type, station.kind) != scene.role:
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


func _drive(scene: Scene, now: int) -> void:
	match scene.role:
		CookingUse.Role.ORDER_BOARD:
			_paint_board(scene)
		CookingUse.Role.HERB_BOARD:
			_paint_pairs(scene)
		CookingUse.Role.BED:
			_paint_bed(scene)
		CookingUse.Role.PLACE:
			_paint_place(scene)
		CookingUse.Role.GRILL:
			_paint_ring(scene, now)


## Rows/RowN for each place numbered N with an order, while this board is bound.
func _paint_board(scene: Scene) -> void:
	var rows: Array[ClientModel.Station] = []
	if scene.station >= 0:
		for id: int in CookingUse.stations_of(model, scene.type, CookingUse.Role.PLACE):
			rows.append(model.stations[id])
	var key := ""
	for station: ClientModel.Station in rows:
		key += "%s/%s/%d;" % [station.bun, station.patty, station.icon]
	if key == scene.painted:
		return
	scene.painted = key
	var row_nodes := scene.part("Rows")
	if row_nodes == null:
		return
	for n in row_nodes.get_child_count():
		var row := row_nodes.get_child(n) as Node3D
		var station: ClientModel.Station = rows[n] if n < rows.size() else null
		var shown := station != null and station.bun != &""
		row.visible = shown
		var number := row.get_node_or_null(^"Number") as Label3D
		if number != null:
			number.text = str(n + 1)
		_picture(row.get_node_or_null(^"Bun"), station.bun if shown else &"", BOARD_PICTURE_M, true)
		_picture(
			row.get_node_or_null(^"Patty"), station.patty if shown else &"", BOARD_PICTURE_M, true
		)
		_icon(row.get_node_or_null(^"Herb"), station.icon if shown else -1)


## Pairs/PairN: icon N-1 and the herb it means, while this board is bound and the herbs dealt.
func _paint_pairs(scene: Scene) -> void:
	var code := model.herb_code if scene.station >= 0 else PackedStringArray()
	var key := ",".join(code)
	if key == scene.painted:
		return
	scene.painted = key
	var pairs := scene.part("Pairs")
	if pairs == null:
		return
	for n in pairs.get_child_count():
		var pair := pairs.get_child(n) as Node3D
		var shown := n < code.size()
		pair.visible = shown
		_icon(pair.get_node_or_null(^"Icon"), n if shown else -1)
		var herb := StringName(code[n]) if shown else &""
		_picture(pair.get_node_or_null(^"Herb"), herb, BOARD_PICTURE_M, true)


## The bed's herb at its Plant: the k-th bed station shows HerbsDealt's k-th bed herb.
func _paint_bed(scene: Scene) -> void:
	var herb := &""
	if scene.station >= 0:
		var k := CookingUse.stations_of(model, scene.type, CookingUse.Role.BED).find(scene.station)
		if k >= 0 and k < model.herb_beds.size():
			herb = StringName(model.herb_beds[k])
	if String(herb) == scene.painted:
		return
	scene.painted = String(herb)
	_picture(scene.part("Plant"), herb, PLANT_M, false)


## A bound place with an order shows its plate and its number (its row on the order board).
func _paint_place(scene: Scene) -> void:
	var station: ClientModel.Station = model.stations.get(scene.station)
	var number := 0
	if station != null and station.bun != &"":
		number = CookingUse.place_number(model, scene.type, scene.station)
	if str(number) == scene.painted:
		return
	scene.painted = str(number)
	var plate := scene.part("Plate")
	if plate != null:
		plate.visible = number > 0
	var label := scene.part("Number") as Label3D
	if label != null:
		label.visible = number > 0
		label.text = str(number)


func _paint_ring(scene: Scene, now: int) -> void:
	var ring := scene.part("Ring")
	if ring == null:
		return
	var station: ClientModel.Station = model.stations.get(scene.station)
	var phase := ring_phase(station, now)
	var lit := roundi(ring_fill(scene.type, station, now) * RING_SEGMENTS)
	ring.visible = phase != Ring.NONE
	var segments := ring.get_node_or_null(^"Segments")
	if segments == null:
		return
	var material := _ring_material(phase == Ring.FRYING)
	for i in segments.get_child_count():
		var segment := segments.get_child(i) as MeshInstance3D
		segment.visible = i < lit
		segment.material_override = material


## The ring's segments replace its scene's whole torus, so a share of it can be lit.
func _build_ring(scene: Scene) -> void:
	var ring := scene.part("Ring") as MeshInstance3D
	if ring == null or ring.get_node_or_null(^"Segments") != null:
		return
	ring.mesh = null
	var segments := Node3D.new()
	segments.name = "Segments"
	ring.add_child(segments)
	for i in RING_SEGMENTS:
		var angle := -TAU * i / RING_SEGMENTS
		var box := BoxMesh.new()
		box.size = Vector3(0.045, 0.02, 0.04)
		var segment := MeshInstance3D.new()
		segment.name = "Segment%d" % i
		segment.mesh = box
		segment.position = Vector3(sin(angle), 0.0, -cos(angle)) * RING_RADIUS_M
		segment.rotation.y = -angle
		segments.add_child(segment)


static func _ring_material(frying: bool) -> StandardMaterial3D:
	if not _ring_materials.has(frying):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = RING_FRYING if frying else RING_BURNING
		_ring_materials[frying] = material
	return _ring_materials[frying]


## Replaces the picture under `marker` with item kind `kind`'s look scaled so its largest side is
## `fit_m` long, a flat look (a patty, a bun) turned to face the board if `on_board` (a kind with
## no look: its name as a label, as the Generator and the photo task do); none for an empty kind.
func _picture(marker: Node, kind: StringName, fit_m: float, on_board: bool) -> void:
	if marker == null:
		return
	_clear(marker)
	if kind == &"":
		return
	var look: Node3D = CookingLooks.build(kind)
	if look == null:
		var label := Label3D.new()
		label.text = ContentNames.text(ContentNames.item(kind, mode))
		label.pixel_size = 0.002
		look = label
	else:
		var size := CookingLooks.size_of(kind)
		look.scale = Vector3.ONE * fit_m / maxf(0.001, maxf(size.x, maxf(size.y, size.z)))
		if on_board and size.y < size.z:
			look.rotation.x = PI / 2.0
	look.name = PICTURE
	marker.add_child(look)


## Replaces the picture under `marker` with icon `index`; none for -1.
func _icon(marker: Node, index: int) -> void:
	if marker == null:
		return
	_clear(marker)
	var texture := CookingLooks.icon(index)
	if texture == null:
		return
	var sprite := Sprite3D.new()
	sprite.name = PICTURE
	sprite.texture = texture
	sprite.pixel_size = ICON_PIXEL_M
	marker.add_child(sprite)


func _clear(marker: Node) -> void:
	var old := marker.get_node_or_null(PICTURE)
	if old != null:
		marker.remove_child(old)
		old.queue_free()
