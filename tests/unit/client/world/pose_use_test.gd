extends GdUnitTestSuite
## What E's Pose reads from the client's own mode copy (#1383): the AtMarker of the first Pose
## action rule (none without a Pose row, none for a row without one or with only a negated one),
## the spawn group of its tag, and whether the feet stand in its cylinder at a marker: the host's
## own geometry (AtMarker.contains), edges included.


func test_the_chair_is_the_pose_rows_at_marker() -> void:
	var mode := FixtureMoves.posing(FixtureItemModes.basic())
	var chair := PoseUse.chair_of(mode)
	assert_object(chair).is_not_null()
	assert_str(String(chair.tag)).is_equal(String(FixtureMoves.SEAT_TAG))
	assert_str(String(PoseUse.group_of(chair))).is_equal("spawn_seat")


func test_no_chair_without_a_pose_row_or_its_at_marker() -> void:
	assert_object(PoseUse.chair_of(null)).is_null()
	assert_object(PoseUse.chair_of(FixtureItemModes.basic())).is_null()
	var bare := FixtureItemModes.basic()
	bare.actions.append(FixtureModes.rule(Intents.POSE, [], [TakePose.new()]))
	assert_object(PoseUse.chair_of(bare)).is_null()
	var negated := FixtureItemModes.basic()
	var at := FixtureMoves.seat_condition()
	at.negate = true
	negated.actions.append(FixtureModes.rule(Intents.POSE, [at], [TakePose.new()]))
	assert_object(PoseUse.chair_of(negated)).is_null()


func test_the_feet_sit_only_inside_a_markers_cylinder() -> void:
	var chair := FixtureMoves.seat_condition()
	var spots := PackedVector3Array([Vector3(5, -3, 0), Vector3(0, 1, 0)])
	var r := FixtureMoves.SEAT_RADIUS_M
	var h := FixtureMoves.SEAT_HEIGHT_M
	assert_bool(PoseUse.at_chair(chair, spots, Vector3(5 + r, -3, 0))).is_true()
	assert_bool(PoseUse.at_chair(chair, spots, Vector3(0, 1 + h, 0))).is_true()
	assert_bool(PoseUse.at_chair(chair, spots, Vector3(5 + r + 0.01, -3, 0))).is_false()
	assert_bool(PoseUse.at_chair(chair, spots, Vector3(0, 0.9, 0))).is_false()
	assert_bool(PoseUse.at_chair(chair, spots, Vector3(0, 1 + h + 0.01, 0))).is_false()
	assert_bool(PoseUse.at_chair(chair, PackedVector3Array(), Vector3(0, 1, 0))).is_false()
	assert_bool(PoseUse.at_chair(null, spots, Vector3(0, 1, 0))).is_false()
