extends GdUnitTestSuite
## The camera wall's chair in the estate house's security room (#1383; GDD §12 "The camera wall"):
## exactly one marker in the spawn group of the base mode's Pose row (its AtMarker's tag), at the
## greybox Chair01, a little below the basement floor's top (the marker is no station marker, so
## nothing snaps it: placed on the floor, float noise could leave a standing player's feet below
## it). A player standing beside the chair, its capsule clear of the chair's box, sits inside the
## row's cylinder; one a step farther does not. The tag is no LayoutCheck demand: a map without the
## chair simply has none.

const HOUSE := "res://levels/estate/rooms/house.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## The basement floor's top (BasementFloor01: y -3.3, 0.2 thick).
const FLOOR_TOP := -3.2
## The player's capsule radius (the base mode's rules: 0.4 m) and Chair01's half width (0.6 m box).
const CAPSULE_RADIUS := 0.4
const CHAIR_HALF := 0.3

var _house: Node3D


func before_test() -> void:
	_house = (load(HOUSE) as PackedScene).instantiate() as Node3D
	add_child(_house)


func after_test() -> void:
	_house.free()


func test_the_security_room_has_one_chair_of_the_base_modes_pose_row() -> void:
	var chair := PoseUse.chair_of(load(BASE_MODE) as GameMode)
	assert_object(chair).is_not_null()
	var spots := _spots(PoseUse.group_of(chair))
	assert_int(spots.size()).is_equal(1)
	var seat_body := _house.get_node("StationMarkers/Chair01") as Node3D
	var at := seat_body.global_position
	var spot := spots[0]
	assert_float(Vector2(spot.x - at.x, spot.z - at.z).length()).is_less(0.01)
	assert_float(spot.y).is_less(FLOOR_TOP)
	assert_float(spot.y).is_greater(FLOOR_TOP - 0.1)
	# Beside the chair (west of it, facing the camera wall to the east), on the floor.
	var beside := Vector3(at.x - CHAIR_HALF - CAPSULE_RADIUS - 0.05, FLOOR_TOP, at.z)
	assert_bool(PoseUse.at_chair(chair, spots, beside)).is_true()
	var farther := Vector3(at.x - chair.radius_m - 0.1, FLOOR_TOP, at.z)
	assert_bool(PoseUse.at_chair(chair, spots, farther)).is_false()
	# One storey up (the ground floor, 3.2 m higher) is no seat.
	assert_bool(PoseUse.at_chair(chair, spots, beside + Vector3(0, 3.2, 0))).is_false()


func _spots(group: StringName) -> PackedVector3Array:
	var spots := PackedVector3Array()
	for node: Node in get_tree().get_nodes_in_group(group):
		assert_object(node as Marker3D).is_not_null()
		if _house.is_ancestor_of(node):
			spots.append((node as Node3D).global_position)
	return spots
