extends GdUnitTestSuite
## HostNode (ARCHITECTURE §4.5): it steps its HostSession from the physics step with the real
## clock, before the default-priority nodes, also while the tree is paused, and leaving the tree
## closes the session.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")


func test_it_steps_the_session_from_the_physics_step_and_closes_it_on_exit() -> void:
	var schema := WireSchema.game(true)
	var session := HostSession.new(
		LoopbackTransport.new(schema.kind_table(), LoopbackHub.new()), schema
	)
	session.replay_dir = ""
	var started := session.start_with(
		Harness.fixture_mode(),
		FlatWorldQuery.new(),
		Harness.layouts(),
		Harness.PORT,
		8,
		HostNode.now_usec(),
		Harness.SEED
	)
	assert_bool(started).is_true()
	var node: HostNode = auto_free(HostNode.new(session))
	assert_int(node.process_physics_priority).is_less(0)
	assert_int(node.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	add_child(node)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(session.game.ticked_through()).is_greater_equal(0)
	remove_child(node)
	assert_bool(session.is_running()).is_false()
	assert_str(String(session.end_reason)).is_equal(String(HostSession.CLOSED))


func test_the_facade_reports_a_refused_start_and_a_debug_build_counters() -> void:
	var schema := WireSchema.game(true)
	var hub := LoopbackHub.new()
	var mode := load("res://content/modes/base_mode.tres") as GameMode
	var first: HostNode = auto_free(
		HostNode.host(LoopbackTransport.new(schema.kind_table(), hub), mode, Harness.PORT)
	)
	first.skip_replay()
	assert_bool(first.is_running()).is_true()
	assert_object(first.own_client).is_not_null()
	assert_array(first.errors).is_empty()
	assert_str(String(first.end_reason)).is_empty()
	assert_bool(OS.is_debug_build()).is_true()
	assert_array(first.counters().keys()).contains_exactly_in_any_order(
		[&"over_budget", &"bad_payloads", &"malformed_disconnects", &"voice_dropped"]
	)
	# The port is taken: the second start is refused and says why.
	var second: HostNode = auto_free(
		HostNode.host(LoopbackTransport.new(schema.kind_table(), hub), mode, Harness.PORT)
	)
	assert_bool(second.is_running()).is_false()
	assert_array(second.errors).is_not_empty()
	first.close()
	assert_bool(first.is_running()).is_false()
	assert_str(String(first.end_reason)).is_equal(String(HostSession.CLOSED))
