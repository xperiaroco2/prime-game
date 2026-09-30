extends GdUnitTestSuite
## The deal's events (ARCHITECTURE §4.2, §5): each class's audience against a state, its
## AUDIENCE_KIND agreeing with audience(), and its payload.

const P1 := 1
const P2 := 2
const P3 := 3


func test_each_deal_event_class_declares_its_audience_kind() -> void:
	var events: Array[MatchEvent] = [
		RoleAssignedEvent.new(P1, &"crew"),
		TeammatesEvent.new(&"dissident", PackedInt32Array([P2])),
		TasksAssignedEvent.new(P1, []),
		StationPlacedEvent.new(1, &"circle", Color.RED, Vector3.ZERO),
		ItemSpawnedEvent.new(1, &"knife", Vector3.ZERO),
		RoundStartedEvent.new(0),
	]
	for event: MatchEvent in events:
		var kind: Variant = (event.get_script() as Script).get_script_constant_map().get(
			"AUDIENCE_KIND"
		)
		(
			assert_int(kind as int)
			. override_failure_message("%s declares no matching AUDIENCE_KIND" % event.event_name())
			. is_equal(event.audience().kind)
		)


func test_recipients() -> void:
	var state := _state()
	(
		assert_array(Array(RoleAssignedEvent.new(P2, &"dissident").audience().recipients(state)))
		. is_equal([P2])
	)
	var teammates := TeammatesEvent.new(&"dissident", PackedInt32Array([P2, P3]))
	assert_array(Array(teammates.audience().recipients(state))).is_equal([P2, P3])
	assert_array(Array(TasksAssignedEvent.new(P3, []).audience().recipients(state))).is_equal([P3])
	var everyone: Array[MatchEvent] = [
		StationPlacedEvent.new(1, &"circle", Color.RED, Vector3.ZERO),
		ItemSpawnedEvent.new(1, &"knife", Vector3.ZERO),
		RoundStartedEvent.new(0),
	]
	for event: MatchEvent in everyone:
		assert_array(Array(event.audience().recipients(state))).is_equal([P1, P2, P3])
	# A dissident who left is no longer told anything.
	state.player(P3).life = PlayerState.Life.LEFT
	assert_array(Array(teammates.audience().recipients(state))).is_equal([P2])


func test_payloads() -> void:
	assert_dict(RoleAssignedEvent.new(P1, &"crew").to_dict()).is_equal({"role": &"crew"})
	assert_dict(TeammatesEvent.new(&"dissident", PackedInt32Array([P2, P3])).to_dict()).is_equal(
		{"role": &"dissident", "peers": PackedInt32Array([P2, P3])}
	)
	var tasks: Array[Dictionary] = [{"task": 4, "type": &"delivery", "subtasks": [{"item": 7}]}]
	assert_dict(TasksAssignedEvent.new(P1, tasks).to_dict()).is_equal({"tasks": tasks})
	assert_dict(StationPlacedEvent.new(2, &"circle", Color.RED, Vector3.ONE).to_dict()).is_equal(
		{"station": 2, "kind": &"circle", "colour": Color.RED, "position": Vector3.ONE}
	)
	assert_dict(ItemSpawnedEvent.new(3, &"knife", Vector3.ONE).to_dict()).is_equal(
		{"item": 3, "kind": &"knife", "position": Vector3.ONE}
	)
	assert_dict(ItemSpawnedEvent.new(3, &"package", Vector3.ONE, 2, Color.RED).to_dict()).is_equal(
		{"item": 3, "kind": &"package", "position": Vector3.ONE, "station": 2, "colour": Color.RED}
	)
	assert_dict(RoundStartedEvent.new(40).to_dict()).is_equal({"start_tick": 40})


func test_an_event_keeps_its_own_copy_of_what_it_was_given() -> void:
	var peers := PackedInt32Array([P2])
	var teammates := TeammatesEvent.new(&"dissident", peers)
	peers.append(P3)
	assert_array(Array(teammates.peers)).is_equal([P2])
	var tasks: Array[Dictionary] = [{"task": 1, "type": &"delivery", "subtasks": []}]
	var assigned := TasksAssignedEvent.new(P1, tasks)
	(tasks[0]["subtasks"] as Array).append({"item": 9})
	assert_array(assigned.tasks[0]["subtasks"] as Array).is_empty()


func _state() -> MatchState:
	var state := MatchState.new(1)
	for peer: int in [P1, P2, P3]:
		state.add_player(peer, "p%d" % peer)
	state.player(P1).role = &"crew"
	state.player(P2).role = &"dissident"
	state.player(P3).role = &"dissident"
	return state
