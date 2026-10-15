extends GdUnitTestSuite
## The cooking task's station scenes (#774, C5; the cooking ADR's CE15): what each holds beyond the
## station convention that station_scenes_test.gd checks for its one-spot devices (the order board,
## the herb board, the grill, the place). The order board holds three numbered rows (CD1's most
## burgers), hidden until an order is posted, each with its bun, patty and herb slots; the herb
## board five icon and herb pairs; the grill its grate (shown, the art's lid hidden) and its timer
## ring (hidden, CD14); the place its plate and its number, both hidden, so an unused place is a
## bare counter. `herb_beds.tscn` holds five beds, each the parent of its use spot in the one
## `spawn_herb_bed` group and of its `Plant`, with a player clear of every bed on each spot; the
## box shelves hold one item marker per box kind on the floor in front, clear of the device, and no
## use spot (they are item markers, not stations). The tags are provisional ("not a decision").

const ORDER_BOARD := "res://levels/stations/order_board.tscn"
const HERB_BOARD := "res://levels/stations/herb_board.tscn"
const GRILL := "res://levels/stations/grill.tscn"
const PLACE := "res://levels/stations/place.tscn"
const HERB_BEDS := "res://levels/stations/herb_beds.tscn"
const BUN_SHELF := "res://levels/stations/bun_shelf.tscn"
const FREEZER := "res://levels/stations/freezer.tscn"
## Each box shelf's item markers' tags, one per box kind (CE7), in scene-tree order.
const BOX_TAGS := {
	BUN_SHELF: [&"box_bun_white", &"box_bun_sesame", &"box_bun_dark"],
	FREEZER: [&"box_patty_light", &"box_patty_red", &"box_patty_deep_red"],
}
## The scenes beyond the one-spot devices, each colliding only through its own `Collision`.
const OTHERS: Array[String] = [HERB_BEDS, BUN_SHELF, FREEZER]
## The order board's rows: CD1's most burgers (3), one row per order.
const ROWS := 3
## The herb board's pairs and the beds: the five herbs (§5.1).
const PAIRS := 5
const BEDS := 5
const BASE_MODE := "res://content/modes/base_mode.tres"
const NEAR := 1e-3
## The capsule's bottom this far above the floor, so the floor under it is no hit.
const FLOOR_GAP_M := 0.05


func test_the_order_board_holds_three_numbered_rows_hidden_until_an_order() -> void:
	var root := _scene(ORDER_BOARD)
	var above := INF
	for i: int in range(1, ROWS + 1):
		var row := root.get_node_or_null("Rows/Row%d" % i) as Node3D
		assert_object(row).override_failure_message("no Rows/Row%d" % i).is_not_null()
		if row == null:
			continue
		assert_bool(row.visible).override_failure_message("Row%d shown" % i).is_false()
		var number := row.get_node_or_null("Number") as Label3D
		assert_object(number).override_failure_message("Row%d: no Number" % i).is_not_null()
		if number != null:
			assert_str(number.text).is_equal(str(i))
		for slot: String in ["Bun", "Patty", "Herb"]:
			var marker := row.get_node_or_null(slot) as Marker3D
			assert_object(marker).override_failure_message("Row%d: no %s" % [i, slot]).is_not_null()
		# Row 1 on top, read downwards.
		assert_float(row.position.y).override_failure_message("Row%d" % i).is_less(above)
		above = row.position.y
	assert_object(root.get_node_or_null("Rows/Row%d" % (ROWS + 1))).is_null()


func test_the_herb_board_holds_five_icon_and_herb_pairs() -> void:
	var root := _scene(HERB_BOARD)
	for i: int in range(1, PAIRS + 1):
		var pair := root.get_node_or_null("Pairs/Pair%d" % i) as Node3D
		assert_object(pair).override_failure_message("no Pairs/Pair%d" % i).is_not_null()
		if pair == null:
			continue
		assert_bool(pair.visible).override_failure_message("Pair%d shown" % i).is_false()
		var icon := pair.get_node_or_null("Icon") as Marker3D
		var herb := pair.get_node_or_null("Herb") as Marker3D
		assert_object(icon).override_failure_message("Pair%d: no Icon" % i).is_not_null()
		assert_object(herb).override_failure_message("Pair%d: no Herb" % i).is_not_null()
		if icon != null and herb != null:
			# The icon on the left, its herb beside it.
			assert_float(icon.position.x).is_less(herb.position.x)
	assert_object(root.get_node_or_null("Pairs/Pair%d" % (PAIRS + 1))).is_null()


func test_the_grill_shows_its_grate_and_hides_its_ring() -> void:
	var root := _scene(GRILL)
	var grate := root.get_node_or_null("Grate") as MeshInstance3D
	var ring := root.get_node_or_null("Ring") as MeshInstance3D
	assert_object(grate).override_failure_message("no Grate mesh").is_not_null()
	assert_object(ring).override_failure_message("no Ring mesh").is_not_null()
	if grate == null or ring == null:
		return
	assert_bool(grate.visible).is_true()
	assert_bool(ring.visible).is_false()
	# The ring hangs over the grate (CD14: a ring over the grill).
	assert_float(ring.position.y).is_greater(grate.position.y)
	# The art's closed lid would hide the grate and the patties on it.
	var lid := root.get_node_or_null("Body/bbq_grill_lid") as Node3D
	assert_object(lid).is_not_null()
	if lid != null:
		assert_bool(lid.visible).is_false()


func test_the_place_hides_its_plate_and_its_number_on_a_bare_counter() -> void:
	var root := _scene(PLACE)
	var plate := root.get_node_or_null("Plate") as MeshInstance3D
	var number := root.get_node_or_null("Number") as Label3D
	assert_object(plate).override_failure_message("no Plate mesh").is_not_null()
	assert_object(number).override_failure_message("no Number label").is_not_null()
	if plate == null or number == null:
		return
	assert_bool(plate.visible).is_false()
	assert_bool(number.visible).is_false()
	# The plate lies on the counter's top, not inside it.
	var counter := root.get_node("Collision/Counter") as CollisionShape3D
	var top := counter.position.y + (counter.shape as BoxShape3D).size.y / 2.0
	assert_float(plate.position.y).is_greater_equal(top)


func test_the_herb_beds_hold_five_beds_each_with_its_use_spot_and_plant() -> void:
	var root := _scene(HERB_BEDS)
	var read := MarkerReader.read(root, HERB_BEDS, HostWorldQuery.new())
	assert_array(Array(read.errors)).is_empty()
	assert_array(read.layout.tags()).is_equal([&"herb_bed"])
	assert_int(read.layout.count(&"herb_bed")).is_equal(BEDS)
	var west := -INF
	for i: int in range(1, BEDS + 1):
		var bed := root.get_node_or_null("Bed%d" % i) as Node3D
		assert_object(bed).override_failure_message("no Bed%d" % i).is_not_null()
		if bed == null:
			continue
		# A name lookup finds the bed, not a collision shape of the same name.
		assert_object(root.find_child("Bed%d" % i, true, false)).is_same(bed)
		var spot := bed.get_node_or_null("UseSpot") as Marker3D
		assert_object(spot).override_failure_message("Bed%d: no UseSpot" % i).is_not_null()
		(
			assert_object(bed.get_node_or_null("Plant"))
			. override_failure_message("Bed%d" % i)
			. is_not_null()
		)
		if spot == null:
			continue
		assert_bool(spot.is_in_group(&"spawn_herb_bed")).is_true()
		# On the floor in front of its bed: the bed's local +Z.
		assert_float(spot.position.y).is_equal_approx(0.0, NEAR)
		assert_float(spot.position.x).is_equal_approx(0.0, NEAR)
		assert_float(spot.position.z).is_greater(0.0)
		# Level order runs west to east, the deal's order of the beds (CE8).
		assert_float(bed.position.x).override_failure_message("Bed%d" % i).is_greater(west)
		west = bed.position.x
	# Every herb_bed marker's parent is a bed of its own: the client binds a bed station to it.
	var parents: Array[Node] = []
	for node: Node in _in_group(root, &"spawn_herb_bed"):
		assert_bool(parents.has(node.get_parent())).is_false()
		assert_str(String(node.get_parent().name)).starts_with("Bed")
		parents.append(node.get_parent())
	assert_int(parents.size()).is_equal(BEDS)


func test_the_beds_and_the_shelves_collide_on_layer_1_only_through_their_own_shapes() -> void:
	for path: String in OTHERS:
		var root := _scene(path)
		var layer_one: Array[String] = []
		for body: CollisionObject3D in _collision_objects(root):
			if (body.collision_layer & LevelWorld.WORLD_LAYER) != 0:
				layer_one.append(String(root.get_path_to(body)))
		assert_array(layer_one).override_failure_message(path).is_equal(["Collision"])
		var collision := root.get_node("Collision") as StaticBody3D
		assert_int(collision.get_child_count()).override_failure_message(path).is_greater(0)
		for child: Node in collision.get_children():
			var shape := child as CollisionShape3D
			var what := "%s: %s" % [path, child.name]
			assert_object(shape).override_failure_message(what).is_not_null()
			if shape != null:
				assert_bool(shape.shape is BoxShape3D).override_failure_message(what).is_true()
		var level := LevelWorld.from_packed(load(path) as PackedScene, path)
		assert_array(Array(level.errors)).override_failure_message(path).is_empty()
		assert_int(level.body_count()).override_failure_message(path).is_equal(1)


func test_a_player_on_each_bed_s_use_spot_stands_clear_of_the_beds() -> void:
	var level := LevelWorld.from_packed(load(HERB_BEDS) as PackedScene, HERB_BEDS)
	var root := _scene(HERB_BEDS)
	for i: int in range(1, BEDS + 1):
		var bed := root.get_node("Bed%d" % i) as Node3D
		var at := bed.position + (bed.get_node("UseSpot") as Marker3D).position
		assert_int(_hits(level, at)).override_failure_message("Bed%d at %s" % [i, at]).is_equal(0)
		# The check can fail: the same capsule on the bed's own floor point.
		assert_int(_hits(level, bed.position)).override_failure_message("Bed%d" % i).is_greater(0)


func test_each_shelf_holds_one_item_marker_per_box_kind_on_the_floor_in_front() -> void:
	for path: String in BOX_TAGS:
		var root := _scene(path)
		var read := MarkerReader.read(root, path, HostWorldQuery.new())
		assert_array(Array(read.errors)).override_failure_message(path).is_empty()
		var tags: Array[StringName] = []
		for node: Node in _in_any_spawn_group(root):
			for group: StringName in node.get_groups():
				if String(group).begins_with("spawn_"):
					tags.append(StringName(String(group).trim_prefix("spawn_")))
		assert_array(tags).override_failure_message(path).is_equal(BOX_TAGS[path])
		# Item markers, not a station: no use spot.
		(
			assert_object(root.find_child("UseSpot", true, false))
			. override_failure_message(path)
			. is_null()
		)
		var level := LevelWorld.from_packed(load(path) as PackedScene, path)
		for node: Node in _in_any_spawn_group(root):
			var marker := node as Marker3D
			var at := _local_position(root, marker)
			var what := "%s: %s at %s" % [path, marker.name, at]
			assert_float(at.y).override_failure_message(what).is_equal_approx(0.0, NEAR)
			assert_float(at.z).override_failure_message(what).is_greater(0.0)
			# The box spawned there stands clear of the device: nothing solid just above the mark.
			(
				assert_int(_point_hits(level, at + Vector3.UP * 0.1))
				. override_failure_message(what)
				. is_equal(0)
			)
		# The check can fail: the same point at the device's middle is inside its collision.
		assert_int(_point_hits(level, Vector3.UP * 0.1)).override_failure_message(path).is_greater(
			0
		)


## The scene at `path`, instantiated and freed with the test.
func _scene(path: String) -> Node3D:
	return auto_free((load(path) as PackedScene).instantiate()) as Node3D


func _collision_objects(node: Node) -> Array[CollisionObject3D]:
	var found: Array[CollisionObject3D] = []
	if node is CollisionObject3D:
		found.append(node as CollisionObject3D)
	for child: Node in node.get_children():
		found.append_array(_collision_objects(child))
	return found


## The nodes under `node` (itself included) in `group`, in scene-tree order (out of the tree).
func _in_group(node: Node, group: StringName) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_in_group(group):
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_in_group(child, group))
	return found


## The nodes under `node` in any `spawn_<tag>` group, in scene-tree order.
func _in_any_spawn_group(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for group: StringName in node.get_groups():
		if String(group).begins_with("spawn_"):
			found.append(node)
			break
	for child: Node in node.get_children():
		found.append_array(_in_any_spawn_group(child))
	return found


## `node`'s position in `root`'s space, out of the tree.
static func _local_position(root: Node, node: Node3D) -> Vector3:
	var at := Transform3D.IDENTITY
	var current: Node = node
	while current != root:
		at = (current as Node3D).transform * at
		current = current.get_parent()
	return at.origin


## How many shapes of the level's world hold the point `at`.
static func _point_hits(level: LevelWorld, at: Vector3) -> int:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = at
	query.collision_mask = LevelWorld.WORLD_LAYER
	return level.space_state().intersect_point(query).size()


## How many shapes of the level's world a standing player's capsule (the base mode's PlayerRules)
## meets with its feet on the floor at `feet`.
static func _hits(level: LevelWorld, feet: Vector3) -> int:
	var rules := (load(BASE_MODE) as GameMode).player_rules
	var capsule := CapsuleShape3D.new()
	capsule.radius = rules.capsule_radius_m
	capsule.height = rules.capsule_height_m - FLOOR_GAP_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	var centre := feet + Vector3.UP * (FLOOR_GAP_M + capsule.height / 2.0)
	query.transform = Transform3D(Basis.IDENTITY, centre)
	return level.space_state().intersect_shape(query).size()
