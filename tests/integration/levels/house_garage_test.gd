extends GdUnitTestSuite
## The art's garage (P6, #1052; prime-game-art assets/room/house_garage/HANDOFF.md) inside the
## game's piece. The car, the lift posts and the lift arms stand where HANDOFF places them in the
## room's frame, now inside the car's station scene (car repair R5, #809): its `Lift` carries the
## car and the arms together, its static frame covers the posts (the art's own colliders are
## off; car_repair_stations_test.gd checks the scene). The lift panel stands 5 m west of the car
## behind its partition (house_car_repair_test.gd), the part picture at HANDOFF's point on the
## east wall, the workbench's drop-off by it; the 8 m gate's leaf is an opening (E4) under its
## solid lintel. And the room keeps each override of a node inside an instance through a re-save
## (the editor's, normalize's, #1056): its instance has an [editable path] entry.

const GARAGE := "res://levels/house/rooms/garage.tscn"
const PROPS := "res://levels/kit/house_props/"
const CAR := "res://levels/stations/car.tscn"
## HANDOFF's lift: node -> [its wrapper, its position in the room].
const LIFT := {
	"Stations/CarLift/Posts": [PROPS + "lift_posts.tscn", Vector3(10, 0, 7)],
	"Stations/CarLift/Lift/Arms": [PROPS + "lift_arms.tscn", Vector3(10, 0.04, 7)],
	"Stations/CarLift/Lift/Body": [PROPS + "garage_car.tscn", Vector3(10, 0, 7)],
}
## The stations: node -> its position in the room. The car and the picture stand at HANDOFF's
## points (the picture's frame on the wall at 1.3 m inside its scene); the panel 5 m west of the
## car's use spot (RD2's placeholder), against the partition's west face. The workbench's
## drop-off stands 1 m east of HANDOFF's (16, 0, 3), whose 1 m cylinder missed the bench's top
## (17.1 to 17.9 m): an item on the top counts there (#831, house_drop_offs_test.gd).
const POINTS := {
	"Stations/CarLift": Vector3(10, 0, 7),
	"Stations/LiftPanel": Vector3(5.75, 0, 7),
	"Stations/PartPicture": Vector3(17.9, 0, 6.5),
	"Stations/Workbench": Vector3(17, 0, 3),
}
const GATE := "Shell/garage_door_8m_1/"
## A section header of the scene's text: its name, its parent, and the rest (type=, instance=).
const HEADER := '^\\[node name="([^"]+)" parent="([^"]+)"(.*)\\]$'
const EDITABLE := '^\\[editable path="([^"]+)"\\]$'

var _garage: Node3D


func before_test() -> void:
	_garage = (load(GARAGE) as PackedScene).instantiate() as Node3D


func after_test() -> void:
	if _garage != null:
		_garage.free()
	_garage = null


func test_the_car_the_posts_and_the_arms_stand_in_the_car_s_station_scene() -> void:
	var car := _garage.get_node_or_null("Stations/CarLift")
	assert_object(car).is_not_null()
	if car == null:
		return
	assert_str(car.scene_file_path).is_equal(CAR)
	for key: String in LIFT:
		var node := _garage.get_node_or_null(NodePath(key)) as Node3D
		assert_object(node).override_failure_message(key).is_not_null()
		if node == null:
			continue
		var expected: Array = LIFT[key]
		assert_str(node.scene_file_path).override_failure_message(key).is_equal(expected[0])
		var at := LevelWorld.transform_in_scene(node, _garage).origin
		(
			assert_bool(at.is_equal_approx(expected[1] as Vector3))
			. override_failure_message("%s at %s" % [key, at])
			. is_true()
		)
	# No art copy of the lift is left in the room's dressing (it would stand a second car).
	for prop: String in ["lift_posts_1", "lift_arms_1", "garage_car_1", "floor_lift_zone_1"]:
		(
			assert_object(_garage.get_node_or_null("Dressing/" + prop))
			. override_failure_message(prop)
			. is_null()
		)


func test_the_stations_stand_at_their_points() -> void:
	for key: String in POINTS:
		var node := _garage.get_node_or_null(NodePath(key)) as Node3D
		assert_object(node).override_failure_message(key).is_not_null()
		if node != null:
			(
				assert_bool(node.position.is_equal_approx(POINTS[key] as Vector3))
				. override_failure_message("%s at %s" % [key, node.position])
				. is_true()
			)


func test_the_gate_s_leaf_is_an_opening_under_a_solid_lintel() -> void:
	var leaf := _garage.get_node(GATE + "garage_door_8m_col1") as StaticBody3D
	var lintel := _garage.get_node(GATE + "garage_door_8m_col0") as StaticBody3D
	assert_int(leaf.collision_layer).is_equal(0)
	assert_int(lintel.collision_layer).is_equal(1)


func test_every_override_inside_an_instance_has_its_editable_path() -> void:
	var missing := _overrides_without_editable(FileAccess.get_file_as_string(GARAGE))
	assert_array(missing).override_failure_message("no [editable path]: %s" % [missing]).is_empty()


func test_an_override_without_its_editable_path_is_named() -> void:
	# The check above can fail: drop the workbench's entry and it names its override.
	var text := FileAccess.get_file_as_string(GARAGE)
	var entry := '[editable path="Dressing/workbench_1"]'
	assert_str(text).contains(entry)
	var missing := _overrides_without_editable(text.replace(entry, ""))
	assert_array(missing).contains_exactly(["Dressing/workbench_1/workbench"])


## The overrides (a node section with neither type= nor instance=: a node of an instanced scene)
## whose parent path and its ancestors have no [editable path] entry in `text`, each as its path.
## None counts as a failure only if the text has overrides at all, so the check is never blind.
func _overrides_without_editable(text: String) -> Array[String]:
	var header := RegEx.create_from_string(HEADER)
	var editable := RegEx.create_from_string(EDITABLE)
	var editables: Array[String] = []
	var overrides: Array[String] = []
	for line: String in text.split("\n"):
		var found := editable.search(line)
		if found != null:
			editables.append(found.get_string(1))
			continue
		found = header.search(line)
		if (
			found != null
			and not ("type=" in found.get_string(3) or "instance=" in found.get_string(3))
		):
			overrides.append("%s/%s" % [found.get_string(2), found.get_string(1)])
	assert_int(overrides.size()).is_greater(100)
	var missing: Array[String] = []
	for path: String in overrides:
		var parent := path.get_base_dir()
		var kept := false
		while not parent.is_empty() and not kept:
			kept = editables.has(parent)
			parent = parent.get_base_dir()
		if not kept:
			missing.append(path)
	return missing
