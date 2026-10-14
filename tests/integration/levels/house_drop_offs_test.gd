extends GdUnitTestSuite
## The House's drop-offs and the furniture each is named after (the Delivery by meaning ADR's DE10
## and DD3 (a), its issue D4, #831): an item put on the furniture's top rests on a layer-1
## collider inside the drop-off's cylinder, so it counts as at its place. The furniture is the
## art's dressing where the art gives it (the dining table, the terrace table, the garage's
## workbench, the garden's drop-off) and the terrace's parasol stand (`levels/props/`), read in
## the host's collision world of the map with the drop-offs where the host's marker reader puts
## them.

const MAP := "res://levels/house/house.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## Each drop-off's spawn tag -> the furniture an item is put on there: its nodes in the House.
const FURNITURE := {
	&"drop_dining_table": ["GroundFloor/DiningRoom/Dressing/dining_table_1"],
	&"drop_terrace_table":
	[
		"GroundFloor/Terrace/Dressing/terrace_table_1",
		"GroundFloor/Terrace/Dressing/parasol_stand_1",
	],
	&"drop_workbench": ["GroundFloor/Garage/Dressing/workbench_1"],
	&"drop_garden": ["Outdoor/Dressing/garden_dropoff_1"],
}
## How far above a collider's top the probe for the surface an item rests on starts.
const PROBE_ABOVE_M := 0.5
## A rest this high over the drop-off's floor lies on the furniture: the probe missed no top and
## found no floor through it.
const TOP_MIN_M := 0.3

var _house: Node


func after_test() -> void:
	if _house != null:
		_house.free()
	_house = null


func test_an_item_on_each_drop_off_s_furniture_rests_inside_its_cylinder() -> void:
	var mode := load(BASE_MODE) as GameMode
	var delivery := mode.find_task_type(&"delivery") as DeliveryByMeaning
	assert_object(delivery).is_not_null()
	if delivery == null:
		return
	var world := HostWorldQuery.new()
	world.add_level(LevelWorld.build(MAP))
	world.use_level(MAP)
	var layout := MarkerReader.read_scene(MAP, world, MarkerReader.floor_tags_of(mode)).layout
	_house = (load(MAP) as PackedScene).instantiate()
	var tags: Array = delivery.station_kinds().map(
		func(kind: StationKind) -> StringName: return kind.spawn_tag
	)
	assert_array(tags).contains_exactly_in_any_order(FURNITURE.keys())
	for kind: StationKind in delivery.station_kinds():
		var markers := layout.positions(kind.spawn_tag)
		assert_int(markers.size()).override_failure_message(kind.spawn_tag).is_equal(1)
		if markers.size() != 1 or not FURNITURE.has(kind.spawn_tag):
			continue
		var drop_off := StationState.new(0, kind, markers[0], Color.WHITE)
		for path: String in FURNITURE[kind.spawn_tag] as Array:
			_assert_tops_inside(world, drop_off, path)


## Every layer-1 collider of the furniture at `path` has its top's centre where an item rests
## inside `drop_off`.
func _assert_tops_inside(world: HostWorldQuery, drop_off: StationState, path: String) -> void:
	var piece := _house.get_node_or_null(NodePath(path)) as Node3D
	assert_object(piece).override_failure_message("no %s in the House" % path).is_not_null()
	if piece == null:
		return
	var tops := _tops(piece)
	assert_array(tops).override_failure_message("%s has no layer-1 collider" % path).is_not_empty()
	for top: Vector3 in tops:
		var rest := world.floor_below(top + Vector3.UP * PROBE_ABOVE_M)
		var where := (
			"%s: an item put on it under %s rests at %s, the drop-off %s at %s"
			% [path, top, rest, drop_off.kind.id, drop_off.position]
		)
		(
			assert_float(rest.y - drop_off.position.y)
			. override_failure_message(where + ": no top under it")
			. is_greater_equal(TOP_MIN_M)
		)
		(
			assert_bool(drop_off.contains(rest))
			. override_failure_message(where + ": outside the cylinder")
			. is_true()
		)


## Over the centre of each layer-1 collision shape under `piece`, in the House's frame, the height
## of the piece's highest top: a probe from there finds whatever an item rests on at that point
## (the parasol stand's tube over its base).
func _tops(piece: Node3D) -> PackedVector3Array:
	var tops := PackedVector3Array()
	var highest := -INF
	for body: Node in piece.find_children("*", "StaticBody3D", true, false):
		if (body as StaticBody3D).collision_layer & LevelWorld.WORLD_LAYER == 0:
			continue
		for child: Node in body.get_children():
			var shape_node := child as CollisionShape3D
			if shape_node == null or shape_node.shape == null:
				continue
			var at := LevelWorld.transform_in_scene(shape_node, _house)
			var box := at * shape_node.shape.get_debug_mesh().get_aabb()
			tops.append(Vector3(box.get_center().x, box.end.y, box.get_center().z))
			highest = maxf(highest, box.end.y)
	for i in tops.size():
		tops[i].y = highest
	return tops
