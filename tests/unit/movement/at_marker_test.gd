extends GdUnitTestSuite
## AtMarker (ARCHITECTURE §9.4, #1383): passes when the actor's last accepted feet stand inside the
## cylinder of any marker of its tag on the level the match plays (MatchContext.layout), radius
## horizontally, edge included, from the marker's height (less StationState.FLOOR_SLACK_M) up to
## height_m above it; a marker of another tag, a level without the tag and no level refuse, with
## `out_of_reach`, and a negated one with `not_allowed`. It reads the actor and no target.

const P1 := 1
const SEAT := Vector3(4, 1, -2)


func test_inside_the_cylinder_passes() -> void:
	for feet: Vector3 in [
		SEAT,
		SEAT + Vector3(0.6, 0, -0.8),
		SEAT + Vector3(1, 0, 0),
		SEAT + Vector3(0, 2, 0),
		SEAT + Vector3(0, -StationState.FLOOR_SLACK_M, 0),
	]:
		(
			assert_bool(_passes(_condition(), feet, [SEAT]))
			. override_failure_message(str(feet))
			. is_true()
		)


func test_outside_the_cylinder_fails_out_of_reach() -> void:
	for feet: Vector3 in [
		SEAT + Vector3(0.8, 0, 0.7),
		SEAT + Vector3(0, 2.01, 0),
		SEAT + Vector3(0, -0.01, 0),
	]:
		(
			assert_bool(_passes(_condition(), feet, [SEAT]))
			. override_failure_message(str(feet))
			. is_false()
		)
	assert_str(_condition().rejection_reason()).is_equal("out_of_reach")


func test_any_marker_of_the_tag_counts() -> void:
	var far := SEAT + Vector3(20, 0, 0)
	assert_bool(_passes(_condition(), far + Vector3(0.5, 0, 0), [SEAT, far])).is_true()


func test_a_marker_of_another_tag_does_not_count() -> void:
	var layout := LevelLayout.new("res://map.tscn")
	layout.add_marker(&"desk", SEAT)
	assert_bool(_passes_on(_condition(), SEAT, layout)).is_false()


func test_a_level_without_the_tag_or_no_level_refuses() -> void:
	assert_bool(_passes(_condition(), SEAT, [])).is_false()
	assert_bool(_passes_on(_condition(), SEAT, null)).is_false()


func test_a_negated_one_passes_away_from_the_seat_and_says_not_allowed() -> void:
	var away := _condition()
	away.negate = true
	assert_bool(_passes(away, SEAT + Vector3(3, 0, 0), [SEAT])).is_true()
	assert_bool(_passes(away, SEAT, [SEAT])).is_false()
	assert_str(away.rejection_reason()).is_equal("not_allowed")


func test_it_reads_the_actor_and_no_target() -> void:
	assert_bool(_condition().reads_actor_state()).is_true()
	assert_bool(_condition().needs_target()).is_false()
	assert_array(_condition().target_facts()).is_empty()


func test_contains_is_the_station_cylinder() -> void:
	# The same geometry as StationState.contains, which the client's key reuses (PoseUse).
	var kind := StationKind.new()
	kind.radius_m = 1.0
	kind.height_m = 2.0
	var station := StationState.new(1, kind, SEAT, Color.WHITE)
	for x in range(-12, 13, 3):
		for y in range(-3, 23, 2):
			var point := SEAT + Vector3(x * 0.1, y * 0.1, 0.35)
			(
				assert_bool(AtMarker.contains(point, SEAT, 1.0, 2.0))
				. override_failure_message(str(point))
				. is_equal(station.contains(point))
			)


func _condition() -> AtMarker:
	var at := AtMarker.new()
	at.tag = &"seat"
	at.radius_m = 1.0
	at.height_m = 2.0
	return at


func _passes(condition: AtMarker, feet: Vector3, seats: Array[Vector3]) -> bool:
	var layout := LevelLayout.new("res://map.tscn")
	for seat: Vector3 in seats:
		layout.add_marker(&"seat", seat)
	return _passes_on(condition, feet, layout)


func _passes_on(condition: AtMarker, feet: Vector3, layout: LevelLayout) -> bool:
	var game := FixtureModes.started(FixtureModes.basic(), [P1])
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.layout = layout
	ctx.actor = P1
	game.state.player(P1).position = feet
	return condition.passes(ctx)
