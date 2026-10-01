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
