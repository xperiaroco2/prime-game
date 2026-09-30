extends GdUnitTestSuite
## Audience (ARCHITECTURE §5): recipients evaluated against the state, and each event class's
## AUDIENCE_KIND agreeing with its audience().

const P1 := 1
const P2 := 2
const P3 := 3


func test_recipients_follow_the_state() -> void:
	var state := MatchState.new(1)
	for peer: int in [P3, P1, P2]:
		state.add_player(peer, "p%d" % peer)
	state.player(P2).role = &"dissident"
	state.player(P3).life = PlayerState.Life.GHOST
	assert_array(Array(Audience.everyone().recipients(state))).is_equal([P1, P2, P3])
	assert_array(Array(Audience.of_role(&"dissident").recipients(state))).is_equal([P2])
	assert_array(Array(Audience.of_life(PlayerState.Life.GHOST).recipients(state))).is_equal([P3])
	assert_array(Array(Audience.only(P2).recipients(state))).is_equal([P2])
	assert_array(Array(Audience.only(9).recipients(state))).is_equal([9])
	assert_array(Array(Audience.server().recipients(state))).is_empty()
	state.player(P2).life = PlayerState.Life.LEFT
	assert_array(Array(Audience.everyone().recipients(state))).is_equal([P1, P3])
	assert_array(Array(Audience.of_role(&"dissident").recipients(state))).is_empty()
	assert_array(Array(Audience.only(P2).recipients(state))).is_empty()


func test_only_never_names_a_peer_id_of_zero_or_less() -> void:
	var state := MatchState.new(1)
	state.add_player(P1, "p1")
	assert_array(Array(Audience.only(0).recipients(state))).is_empty()
	assert_array(Array(Audience.only(-1).recipients(state))).is_empty()
	state.remove_player(P1)
	# A peer removed from the roster is a connected non-player again: only its Rejected reaches it.
	assert_array(Array(Audience.only(P1).recipients(state))).is_equal([P1])


func test_each_event_class_declares_its_audience_kind() -> void:
	var events: Array[MatchEvent] = [
		PhaseChangedEvent.new(&"lobby", -1),
		PlayersPlacedEvent.new({}),
		CorrectionEvent.new(P1, 1, Vector3.ZERO, Vector3.ZERO),
		RejectedEvent.new(P1, 0, &"x"),
		ItemSpawnedEvent.new(1, &"package", Vector3.ZERO),
		StationPlacedEvent.new(1, &"circle", Color.RED, Vector3.ZERO),
		TasksAssignedEvent.new(P1, []),
		PackageDeliveredEvent.new(1, 1),
		TaskProgressEvent.new(0, 1),
		TaskUpdatedEvent.new(P1, 1, 0),
	]
	for event: MatchEvent in events:
		var declared: Variant = (event.get_script() as Script).get_script_constant_map().get(
			"AUDIENCE_KIND"
		)
		assert_int(event.audience().kind).is_equal(declared)
