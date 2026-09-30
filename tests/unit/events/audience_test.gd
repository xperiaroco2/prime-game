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
	assert_array(Array(Audience.sender(P2).recipients(state))).is_equal([P2])
	assert_array(Array(Audience.server().recipients(state))).is_empty()
	state.player(P2).life = PlayerState.Life.LEFT
	assert_array(Array(Audience.everyone().recipients(state))).is_equal([P1, P3])
	assert_array(Array(Audience.of_role(&"dissident").recipients(state))).is_empty()
	assert_array(Array(Audience.only(P2).recipients(state))).is_empty()
	assert_array(Array(Audience.sender(P2).recipients(state))).is_empty()


func test_only_and_sender_never_name_a_peer_id_of_zero_or_less() -> void:
	var state := MatchState.new(1)
	state.add_player(P1, "p1")
	assert_array(Array(Audience.only(0).recipients(state))).is_empty()
	assert_array(Array(Audience.only(-1).recipients(state))).is_empty()
	assert_array(Array(Audience.sender(0).recipients(state))).is_empty()
	assert_array(Array(Audience.sender(-1).recipients(state))).is_empty()


func test_only_a_sender_reaches_a_peer_that_is_not_a_player() -> void:
	# The engineer's answer on #49: a connected non-player (no accepted Hello yet, or removed from
	# the roster) gets its Rejected through SENDER, and nothing through ONLY.
	var state := MatchState.new(1)
	assert_array(Array(Audience.only(9).recipients(state))).is_empty()
	assert_array(Array(Audience.sender(9).recipients(state))).is_equal([9])
	state.add_player(P1, "p1")
	state.remove_player(P1)
	assert_array(Array(Audience.only(P1).recipients(state))).is_empty()
	assert_array(Array(Audience.sender(P1).recipients(state))).is_equal([P1])


func test_each_event_class_declares_its_audience_kind() -> void:
	var events: Array[MatchEvent] = [
		PhaseChangedEvent.new(&"lobby", -1),
		PlayersPlacedEvent.new({}),
		CorrectionEvent.new(P1, 1, Vector3.ZERO, Vector3.ZERO),
		RejectedEvent.new(P1, 0, &"x"),
	]
	for event: MatchEvent in events:
		var declared: Variant = (event.get_script() as Script).get_script_constant_map().get(
			"AUDIENCE_KIND"
		)
		assert_int(event.audience().kind).is_equal(declared)
