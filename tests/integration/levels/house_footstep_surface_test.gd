extends GdUnitTestSuite
## Footsteps on the House sound its floors (#1042, #525; ARCHITECTURE §4.7.43): over each piece of
## house.tscn (the nodes under a floor group that declare size_m), on a grid of points STEP_M apart
## inside its footprint at its floor's height (its origin's), FootstepSurface's own ray down (from
## ABOVE_M over the feet to BELOW_M under them, on the world layer) hits a collider that carries a
## `surface` tag of its own or an ancestor's (FootstepSurface.META), one of
## FootstepSurface.SURFACES: never the untagged default a missing tag falls back to. The floors are
## the art's: its rooms' Shell pieces and the plot's Ground and Shell (house/outdoor.tscn), which
## carry the tags; a prop's collider (Dressing, Detail) is switched off here, so the rays find the
## floor under it. A point with no floor under it (a stairwell, a gap) is no step and is skipped;
## each piece has at least one point on a floor. The world is the client's: house.tscn in a tree of
## its own (a SubViewport with its own World3D), as the client plays it, since the host's
## LevelWorld keeps no nodes and so no tags.

const HOUSE := "res://levels/house/house.tscn"
## The grid's spacing, and its inset from a footprint's edges (on a wall's foot: a denser band hits
## the exterior walls' tops, which are no floor).
const STEP_M := 1.0
const INSET_M := 0.5

var _viewport: SubViewport
var _house: Node3D


func before_test() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	add_child(_viewport)
	_house = (load(HOUSE) as PackedScene).instantiate() as Node3D
	for node: Node in _house.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		shape.disabled = shape.disabled or not _floor_piece(_house.get_path_to(shape))
	_viewport.add_child(_house)


func after_test() -> void:
	if _viewport != null:
		remove_child(_viewport)
		_viewport.free()
	_viewport = null
	_house = null


func test_every_floor_of_every_piece_carries_a_surface_tag() -> void:
	await get_tree().physics_frame
	var found := _walk()
	assert_int(found["pieces"]).is_greater(30)
	var no_floor: Array[String] = found["no_floor"]
	(
		assert_array(no_floor)
		. override_failure_message("no floor found on %s" % ", ".join(no_floor))
		. is_empty()
	)
	var lines := _lines(found["untagged"])
	(
		assert_array(lines)
		. override_failure_message("steps on an untagged floor:\n" + "\n".join(lines))
		. is_empty()
	)


func test_the_walk_reports_a_piece_whose_tags_are_removed() -> void:
	# The walk above can fail: strip every tag under the bedroom and it names the bedroom's floor.
	await get_tree().physics_frame
	assert_array(_lines(_walk()["untagged"])).is_empty()
	var bedroom := _house.get_node(^"SecondFloor/Bedroom")
	var stripped := 0
	for node: Node in [bedroom] + bedroom.find_children("*", "", true, false):
		if node.has_meta(FootstepSurface.META):
			node.remove_meta(FootstepSurface.META)
			stripped += 1
	assert_int(stripped).is_greater(0)
	var lines := _lines(_walk()["untagged"])
	var named: Array[String] = lines.filter(func(line: String) -> bool: return "/Bedroom:" in line)
	assert_array(named).is_not_empty()


func test_a_tag_is_read_from_an_ancestor_and_a_missing_one_is_the_default() -> void:
	# The yard's first round spawn stands on the plot's Ground, whose tag is its own; without it the
	# same ray finds no tag, and FootstepSurface plays its default.
	await get_tree().physics_frame
	var space := _house.get_world_3d().direct_space_state
	var spawn := _house.get_tree().get_nodes_in_group(&"spawn_round_player")[0] as Node3D
	var hit := _floor_hit(space, spawn.global_position)
	assert_bool(hit.is_empty()).is_false()
	if hit.is_empty():
		return
	var collider := hit["collider"] as Node
	assert_str(String(_tag_of(collider))).is_equal("grass")
	var tagged := collider
	while not tagged.has_meta(FootstepSurface.META):
		tagged = tagged.get_parent()
	tagged.remove_meta(FootstepSurface.META)
	assert_str(String(_tag_of(collider))).is_equal("")
	assert_str(String(FootstepSurface.of(collider))).is_equal(String(FootstepSurface.DEFAULT))


## The grid walk over every piece: {pieces: the pieces walked, no_floor: the pieces with no floor
## point, untagged: "piece: collider path" -> the points that step on an untagged collider}.
func _walk() -> Dictionary:
	var space := _house.get_world_3d().direct_space_state
	var untagged: Dictionary[String, int] = {}
	var no_floor: Array[String] = []
	var pieces := 0
	for group: Node in _house.get_children():
		for piece: Node in group.get_children():
			if not piece.has_meta(&"size_m"):
				continue
			var key := "%s/%s" % [group.name, piece.name]
			pieces += 1
			var hits := 0
			var footprint := _footprint(piece as Node3D)
			var x := footprint.position.x + INSET_M
			while x < footprint.end.x:
				var z := footprint.position.z + INSET_M
				while z < footprint.end.z:
					var feet := Vector3(x, (piece as Node3D).global_position.y, z)
					z += STEP_M
					var hit := _floor_hit(space, feet)
					if hit.is_empty():
						continue
					hits += 1
					var collider := hit["collider"] as Node
					if _tag_of(collider) == &"":
						var where := "%s: %s" % [key, _house.get_path_to(collider)]
						untagged[where] = untagged.get(where, 0) + 1
				x += STEP_M
			if hits == 0:
				no_floor.append(key)
	return {"pieces": pieces, "no_floor": no_floor, "untagged": untagged}


static func _lines(found: Variant) -> Array[String]:
	var lines: Array[String] = []
	var untagged := found as Dictionary
	for where: String in untagged:
		lines.append("%s (%d points)" % [where, untagged[where]])
	return lines


## Whether the collision shape at `path` (from the House's root) is a floor's: a piece's Shell
## (the art's rooms), the plot's Ground and its Shell. A prop's (Dressing, Detail) is not.
static func _floor_piece(path: NodePath) -> bool:
	var parts := String(path).split("/")
	if parts.size() > 2 and parts[0] == "Outdoor":
		return parts[1] == "Ground" or parts[1] == "Shell"
	return parts.size() > 3 and parts[2] == "Shell"


## A piece's footprint at its floor's height: from its origin (the north-west floor corner) over
## its size_m, 0.1 m above and below that floor (never a point of another storey).
static func _footprint(piece: Node3D) -> AABB:
	var size: Vector2i = piece.get_meta(&"size_m")
	return AABB(piece.global_position + Vector3.DOWN * 0.1, Vector3(size.x, 0.2, size.y))


## FootstepSurface.under's ray at `feet`: the hit, or empty for no floor.
static func _floor_hit(space: PhysicsDirectSpaceState3D, feet: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		feet + Vector3.UP * FootstepSurface.ABOVE_M,
		feet + Vector3.DOWN * FootstepSurface.BELOW_M,
		PhysicsLayers.WORLD
	)
	return space.intersect_ray(query)


## The tag FootstepSurface.of reads on `collider` (its own or its nearest tagged ancestor's), when
## it is one of SURFACES; &"" when there is none or it names no surface.
static func _tag_of(collider: Node) -> StringName:
	var node := collider
	while node != null:
		if node.has_meta(FootstepSurface.META):
			var tag: Variant = node.get_meta(FootstepSurface.META)
			if tag is String or tag is StringName:
				var surface := StringName(tag as String)
				return surface if surface in FootstepSurface.SURFACES else &""
			return &""
		node = node.get_parent()
	return &""
