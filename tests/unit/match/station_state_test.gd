extends GdUnitTestSuite
## StationState.contains (ARCHITECTURE §7.1.14, ZE2 of the zone task ADR): the one cylinder test
## of a station, which Delivery asks with a package's rest position and the zone task with a
## player's feet: within the radius horizontally, edges included, and from the floor (with
## FLOOR_SLACK_M of float noise below it) up to the height.


## Delivery's test of its circle (radius 1 m, height 2 m), moved here with its cylinder test.
func test_the_cylinder_includes_its_edges_and_nothing_beyond() -> void:
	var circle := StationState.new(1, FixtureDeliveryModes.circle(), Vector3(4, 1, -3), Color.RED)
	var inside: Array[Vector3] = [
		Vector3(4, 1, -3),
		Vector3(4, 0.9995, -3),
		Vector3(5, 1, -3),
		Vector3(4, 1, -2),
		Vector3(4.6, 2, -2.3),
		Vector3(4, 3, -3),
		Vector3(3, 3, -3),
	]
	for at: Vector3 in inside:
		assert_bool(circle.contains(at)).override_failure_message(str(at)).is_true()
	var outside: Array[Vector3] = [
		Vector3(5.01, 1, -3),
		Vector3(4.8, 1, -2.3),
		Vector3(4, 0.99, -3),
		Vector3(4, 3.01, -3),
		Vector3(4, -1, -3),
	]
	for at: Vector3 in outside:
		assert_bool(circle.contains(at)).override_failure_message(str(at)).is_false()


## A zone's cylinder (radius 1.5 m, height 2.5 m) with a player's feet: on the floor counts, within
## the floor's float slack below it counts, past it (2 mm below) does not; at the height counts,
## 1 cm above does not; on the radius counts, 1 cm beyond does not.
func test_feet_count_on_the_floor_and_up_to_the_height_and_radius() -> void:
	var kind := StationKind.new()
	kind.radius_m = 1.5
	kind.height_m = 2.5
	var zone := StationState.new(2, kind, Vector3(-2, 0.5, 6), Color.YELLOW)
	var inside: Array[Vector3] = [
		Vector3(-2, 0.5, 6),
		Vector3(-2, 0.5 - StationState.FLOOR_SLACK_M / 2.0, 6),
		Vector3(-2, 3.0, 6),
		Vector3(-0.5, 0.5, 6),
		Vector3(-2, 0.5, 4.5),
	]
	for at: Vector3 in inside:
		assert_bool(zone.contains(at)).override_failure_message(str(at)).is_true()
	var outside: Array[Vector3] = [
		Vector3(-2, 0.498, 6),
		Vector3(-2, 3.01, 6),
		Vector3(-0.49, 0.5, 6),
		Vector3(-2, 0.5, 4.49),
	]
	for at: Vector3 in outside:
		assert_bool(zone.contains(at)).override_failure_message(str(at)).is_false()
