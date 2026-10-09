class_name MapData
extends RefCounted
## What the map screen draws of the level (#253, ARCHITECTURE §4.7.30): its rooms and, for each
## task type, the rooms where its items may lie (the zones). Pure: read once from the level when it
## loads, from level data every client has, never from the model: no player, item or circle.
##
## A room is a Node3D of the level with `metadata/size_m` (Vector2i or Vector2, whole metres), the
## level piece conventions (PR #611): its origin is its north-west floor corner, its plan rect runs
## `size_m` from there along +X and +Z, unrotated; plan x is X and plan y is Z. Its id is its
## `metadata/room_id`, else its node name in snake_case; the screen names it by the deck key
## `room.<id>`. Only rooms_of() reads this shape, so #306's room record changes that one function.
##
## A task type's zones are the rooms holding a level marker (a Marker3D in the group `spawn_<tag>`)
## of one of its TaskType.item_spawn_tags(): every such marker, never the ones a deal chose, so a
## lit room says what the level says and nothing of where the items are now.

## A room's size in metres, on the room node (PR #611's convention).
const SIZE_KEY := &"size_m"
## A room's id, when its node name is not it.
const ID_KEY := &"room_id"
## The spawn points' group prefix (MarkerReader's, which client/ may not name).
const SPAWN_GROUP_PREFIX := "spawn_"
## The empty border around the rooms on the board, a share of the board's shorter side (layout).
const MARGIN := 0.05


## One room on the plan, in metres: `rect.position` its north-west corner (X, Z).
class Room:
	extends RefCounted
	var id: StringName
	var rect: Rect2

	func _init(room_id: StringName, plan_rect: Rect2) -> void:
		id = room_id
		rect = plan_rect


var rooms: Array[Room] = []
## Task type id -> the ids of the rooms where its items may lie, in room order.
var zones: Dictionary[StringName, PackedStringArray] = {}


## The rooms of `level` and, for each task type of `mode`, its zones; empty for no level.
static func from_level(level: Node, mode: GameMode) -> MapData:
	var data := MapData.new()
	if level == null:
		return data
	data.rooms = rooms_of(level)
	if mode == null:
		return data
	var markers: Array[Node] = level.find_children("*", "Marker3D", true, false)
	for type: TaskType in mode.task_types:
		if type == null:
			continue
		var lit: Array[StringName] = []
		for tag: StringName in type.item_spawn_tags():
			for marker: Node in markers:
				if not marker.is_in_group(StringName(SPAWN_GROUP_PREFIX + tag)):
					continue
				if _spawn_groups_of(marker) > 1:
					continue
				var room := data.room_at(plan_of(_placed(marker as Node3D, level).origin))
				if room != null and not lit.has(room.id):
					lit.append(room.id)
		var ordered := PackedStringArray()
		for room: Room in data.rooms:
			if lit.has(room.id):
				ordered.append(room.id)
		data.zones[type.id] = ordered
	return data


## The rooms under `level`, in scene-tree order (the room reader of #253 until #306's record).
static func rooms_of(level: Node) -> Array[Room]:
	var found: Array[Room] = []
	var taken: Array[StringName] = []
	var nodes: Array[Node] = [level]
	nodes.append_array(level.find_children("*", "Node3D", true, false))
	for node: Node in nodes:
		var room := node as Node3D
		if room == null or not room.has_meta(SIZE_KEY):
			continue
		var given: Variant = room.get_meta(SIZE_KEY)
		var size := Vector2.ZERO
		if given is Vector2i:
			size = Vector2(given as Vector2i)
		elif given is Vector2:
			size = given as Vector2
		else:
			continue
		var id := StringName(str(room.get_meta(ID_KEY, String(room.name).to_snake_case())))
		if taken.has(id):
			push_warning("MapData: the room %s repeats the id %s, left out" % [room.get_path(), id])
			continue
		taken.append(id)
		var corner := plan_of(_placed(room, level).origin)
		found.append(Room.new(id, Rect2(corner, size)))
	return found


## A point of the level on the plan: X and Z.
static func plan_of(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)


## The room whose rect holds `plan_point`, the first in room order; null outside every room.
func room_at(plan_point: Vector2) -> Room:
	for room: Room in rooms:
		if room.rect.has_point(plan_point):
			return room
	return null


## The ids of the rooms where the items of `task_type` may lie; empty for an unknown type.
func zone_of(task_type: StringName) -> PackedStringArray:
	return zones.get(task_type, PackedStringArray())


## Every room's rect together; zero size with no room.
func bounds() -> Rect2:
	if rooms.is_empty():
		return Rect2()
	var all := rooms[0].rect
	for room: Room in rooms:
		all = all.merge(room.rect)
	return all


## Pixels per metre on a board of `board` pixels: the rooms fit inside the margin, one scale for
## both axes so a square room stays square.
func scale_for(board: Vector2) -> float:
	var area := bounds()
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return 0.0
	var room_for := board - Vector2.ONE * 2.0 * MARGIN * minf(board.x, board.y)
	return minf(room_for.x / area.size.x, room_for.y / area.size.y)


## Where the plan point `plan_point` lies on a board of `board` pixels, the rooms centred on it.
func to_board(plan_point: Vector2, board: Vector2) -> Vector2:
	var area := bounds()
	var scale := scale_for(board)
	var offset := (board - area.size * scale) / 2.0
	return offset + (plan_point - area.position) * scale


## `node`'s transform in the level scene `root`, as the host's MarkerReader places a marker
## (LevelWorld.transform_in_scene, which client/ may not name): through its Node3D parents up to and
## including `root`, and no further than a top_level node.
static func _placed(node: Node3D, root: Node) -> Transform3D:
	var placed := node.transform
	var current := node
	while not current.top_level and current != root and current.get_parent() is Node3D:
		current = current.get_parent() as Node3D
		placed = current.transform * placed
	return placed


## How many spawn groups `marker` is in; the host's MarkerReader refuses more than one.
static func _spawn_groups_of(marker: Node) -> int:
	var count := 0
	for group: StringName in marker.get_groups():
		if String(group).begins_with(SPAWN_GROUP_PREFIX):
			count += 1
	return count
