extends GdUnitTestSuite
## Footsteps on the House sound its floors (#1042, #525; ARCHITECTURE §4.7.40): over each piece of
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
##
## The garage (GREYBOX) stays the greybox's until the art's P6 (#523): its boxes carry no tag, so
## every step there is the default; points in its footprint are skipped, and a GREYBOX piece with
## an art Shell fails, so P6's import tags it and takes it off the list.

const HOUSE := "res://levels/house/house.tscn"
## The pieces with no tag yet: greybox, no art Shell (until the art's P6).
const GREYBOX: Array[String] = ["GroundFloor/Garage"]
## The grid's spacing, and its inset from a footprint's edges (on a wall's foot).
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
	var space := _house.get_world_3d().direct_space_state
	var untagged: Dictionary[String, int] = {}
	var no_floor: Array[String] = []
	var pieces := 0
	var greybox: Array[AABB] = []
	for key: String in GREYBOX:
		greybox.append(_footprint(_house.get_node(NodePath(key)) as Node3D))
	for group: Node in _house.get_children():
		for piece: Node in group.get_children():
			if not piece.has_meta(&"size_m"):
				continue
			var key := "%s/%s" % [group.name, piece.name]
			if GREYBOX.has(key):
				continue
			pieces += 1
			var hits := 0
			var footprint := _footprint(piece as Node3D)
			var x := footprint.position.x + INSET_M
			while x < footprint.end.x:
				var z := footprint.position.z + INSET_M
				while z < footprint.end.z:
					var feet := Vector3(x, (piece as Node3D).global_position.y, z)
					z += STEP_M
					if greybox.any(func(box: AABB) -> bool: return box.has_point(feet)):
						continue
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
	assert_int(pieces).is_greater(30)
	(
		assert_array(no_floor)
		. override_failure_message("no floor found on %s" % ", ".join(no_floor))
		. is_empty()
	)
	var lines: Array[String] = []
	for where: String in untagged:
		lines.append("%s (%d points)" % [where, untagged[where]])
	(
		assert_array(lines)
		. override_failure_message("steps on an untagged floor:\n" + "\n".join(lines))
		. is_empty()
	)


func test_the_check_finds_an_untagged_floor_and_reads_a_tag_from_an_ancestor() -> void:
	# The check above can fail: the yard's first round spawn stands on the plot's Ground, whose tag
	# is its own; without it the same ray finds no tag.
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


func test_the_greybox_pieces_have_no_art_shell_yet() -> void:
	for key: String in GREYBOX:
		var piece := _house.get_node_or_null(NodePath(key))
		assert_object(piece).override_failure_message(key).is_not_null()
		if piece != null:
			(
				assert_bool(piece.has_node(^"Shell"))
				. override_failure_message(
					"%s has the art's Shell: tag it, drop it from GREYBOX" % key
				)
				. is_false()
			)


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
				var name := StringName(tag as String)
				return name if name in FootstepSurface.SURFACES else &""
			return &""
		node = node.get_parent()
	return &""
