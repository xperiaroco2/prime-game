extends GdUnitTestSuite
## The House map's stairs can be walked (docs/design/house-map.md §5): along each flight, from the
## floor in front of its bottom step to the floor beyond its top, every rise is a step the player
## can take (rules.step_height_m, 0.3 m) and the player's capsule, resting on the step edges, fits:
## no wall in the way, room for the head under the floor above. Read in the host's collision world
## of the level (LevelWorld), the world the host checks movement against.

const MAP := "res://levels/house/house.tscn"
const RADIUS := 0.4
const HEIGHT := 1.8
const STEP := 0.3
const SPACING := 0.1
## Where the walk starts and every corner it turns, in map coordinates; y is the start's floor.
const WALKS := {
	"main stairs, ground floor to landing":
	[Vector3(32.5, 0, 35.4), Vector3(28, 0, 35.4), Vector3(28, 0, 30.6)],
	"pantry stairs, storage to pantry":
	[Vector3(25.1, -3.2, 25.2), Vector3(25.1, -3.2, 29.4), Vector3(27.6, -3.2, 29.4)],
	"outdoor stairs, passage to yard": [Vector3(60.8, -3.2, 31), Vector3(66.8, -3.2, 31)],
	"external stairs, terrace to balcony": [Vector3(39, 0, 16.4), Vector3(39, 0, 21.6)],
	"attic stairs, landing to attic":
	[Vector3(33.05, 3.2, 30.9), Vector3(33.05, 3.2, 26.7), Vector3(31, 3.2, 26.7)],
}
## How high each walk ends: the level it leads to.
const ENDS := {
	"main stairs, ground floor to landing": 3.2,
	"pantry stairs, storage to pantry": 0.0,
	"outdoor stairs, passage to yard": -0.06,
	"external stairs, terrace to balcony": 3.2,
	"attic stairs, landing to attic": 6.4,
}

var _level: LevelWorld


func before() -> void:
	_level = LevelWorld.build(MAP)


func after() -> void:
	_level = null


func test_the_map_builds_into_the_host_s_world_without_errors() -> void:
	assert_array(Array(_level.errors)).is_empty()
	assert_int(_level.body_count()).is_greater(0)


func test_each_flight_can_be_walked_from_bottom_to_top() -> void:
	for walk: String in WALKS:
		var corners: Array = WALKS[walk]
		var floor_y := (corners[0] as Vector3).y
		var start := true
		for at in _points(corners):
			var found := _rest_height(at.x, at.z, floor_y)
			(
				assert_bool(is_nan(found))
				. override_failure_message("%s: no floor under (%.2f, %.2f)" % [walk, at.x, at.z])
				. is_false()
			)
			if is_nan(found):
				break
			if not start:
				(
					assert_float(found - floor_y)
					. override_failure_message(
						"%s: a %.2f m rise at (%.2f, %.2f)" % [walk, found - floor_y, at.x, at.z]
					)
					. is_less_equal(STEP)
				)
			floor_y = found
			start = false
			(
				assert_bool(_fits(Vector3(at.x, floor_y, at.z)))
				. override_failure_message(
					(
						"%s: the player does not fit at (%.2f, %.2f, %.2f)"
						% [walk, at.x, floor_y, at.z]
					)
				)
				. is_true()
			)
		var end: float = ENDS[walk]
		(
			assert_float(floor_y)
			. override_failure_message("%s ends at %.2f, not at %.2f" % [walk, floor_y, end])
			. is_equal_approx(end, 0.01)
		)


## The walk's points every SPACING metres along its corners.
func _points(corners: Array) -> Array[Vector3]:
	var out: Array[Vector3] = [corners[0] as Vector3]
	for i in range(1, corners.size()):
		var a := corners[i - 1] as Vector3
		var b := corners[i] as Vector3
		var n := ceili(Vector2(b.x - a.x, b.z - a.z).length() / SPACING)
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / n))
	return out


## How high the player's capsule rests at (x, z): on the highest floor under its circle, as on a
## stair it rests on the step edges; NAN when there is no floor under it at all. Sampled at the
## centre and on two rings, a little pessimistic (it lifts the capsule a hair too much).
func _rest_height(x: float, z: float, last: float) -> float:
	var top := _floor_under(x, z, last)
	for ring: float in [RADIUS / 2, RADIUS * 0.98]:
		for k in 8:
			var angle := TAU * k / 8
			var under := _floor_under(x + cos(angle) * ring, z + sin(angle) * ring, last)
			if not is_nan(under) and (is_nan(top) or under > top):
				top = under
	return top


## The top of the floor under (x, z), searched from a step above the last floor down to 1 m
## below it; NAN when there is none.
func _floor_under(x: float, z: float, last: float) -> float:
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(x, last + STEP + 0.05, z), Vector3(x, last - 1.0, z), LevelWorld.WORLD_LAYER
	)
	var hit := _level.space_state().intersect_ray(ray)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y


## Whether the player's capsule, resting with its feet at `feet`, touches nothing: no wall in the
## way and room for the head.
func _fits(feet: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, HEIGHT / 2 + 0.02, 0))
	return _level.space_state().intersect_shape(query, 1).is_empty()
