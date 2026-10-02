extends GdUnitTestSuite
## The steps of a playcheck window (tools/playcheck/playcheck_steps.gd, #186): waits that pass at
## once or time out at their timeout and not before, frames, actions, the host's setup and event
## matching through player numbers, over a fake View and a fake clock (no window, no sleep). The
## plan comes from tools/runner/playcheck.py (its parser: tools/runner/tests/test_playcheck.py).

const Steps := preload("res://tools/playcheck/playcheck_steps.gd")


class FakeView:
	extends Steps.View
	var is_welcomed := true
	var phase_now := "lobby"
	var own := 7
	var peers: Dictionary[int, int] = {1: 7, 2: 9}
	var lives: Dictionary[int, String] = {}
	var roster := 2
	var received: Array[Array] = []
	var screen_now := "lobby"
	var esc_now := false

	func welcomed() -> bool:
		return is_welcomed

	func screen() -> String:
		return screen_now

	func esc_open() -> bool:
		return esc_now

	func phase() -> String:
		return phase_now

	func own_peer() -> int:
		return own

	func peer_of(player: int) -> int:
		return peers.get(player, 0)

	func roster_size() -> int:
		return roster

	func life_of(peer: int) -> String:
		return lives.get(peer, "alive")

	func events() -> Array[Array]:
		return received


class EndedView:
	extends FakeView

	func unwelcomed() -> String:
		return "no session: it ended (host_lost)"


func _wait(what: String, value: Variant, timeout_s := 2.0, line := 5) -> Dictionary:
	return {
		"line": line,
		"text": "wait %s %s" % [what, value],
		"do": "wait",
		"what": what,
		"value": value,
		"timeout_s": timeout_s
	}


func _steps(plan: Array[Dictionary], view: FakeView) -> Steps:
	return Steps.new(plan, view)


func test_a_wait_that_holds_passes_at_once_and_the_next_action_comes_in_the_same_frame() -> void:
	var shot := {"line": 6, "text": "shot lobby", "do": "shot", "name": "lobby"}
	var steps := _steps([_wait("phase", "lobby"), shot], FakeView.new())
	assert_dict(steps.advance(0)).is_equal(shot)
	assert_int(steps.index).is_equal(2)
	assert_dict(steps.advance(16)).is_empty()
	assert_int(steps.status).is_equal(Steps.Status.DONE)


func test_a_wait_times_out_at_its_timeout_and_not_before_naming_its_line_and_what_it_saw() -> void:
	var view := FakeView.new()
	var steps := _steps([_wait("phase", "round", 2.0, 12)], view)
	assert_dict(steps.advance(1000)).is_empty()
	assert_dict(steps.advance(2999)).is_empty()
	assert_int(steps.status).is_equal(Steps.Status.RUNNING)
	assert_dict(steps.advance(3000)).is_empty()
	assert_int(steps.status).is_equal(Steps.Status.FAILED)
	assert_str(steps.failure).is_equal(
		"step 1 (line 12: wait phase round): timed out after 2.0 s; the window saw phase 'lobby'"
	)
	# A failed run stays failed, even if the wait would hold now.
	view.phase_now = "round"
	steps.advance(3100)
	assert_int(steps.status).is_equal(Steps.Status.FAILED)


func test_each_wait_has_its_own_timeout_from_its_own_start() -> void:
	var view := FakeView.new()
	var steps := _steps([_wait("phase", "lobby"), _wait("phase", "round", 1.0)], view)
	steps.advance(5000)
	assert_int(steps.index).is_equal(1)
	steps.advance(5999)
	assert_int(steps.status).is_equal(Steps.Status.RUNNING)
	view.phase_now = "round"
	steps.advance(5999)
	assert_int(steps.status).is_equal(Steps.Status.DONE)


func test_a_window_without_a_session_says_what_it_has_instead() -> void:
	var view := EndedView.new()
	view.is_welcomed = false
	var steps := _steps([_wait("phase", "lobby", 1.0)], view)
	steps.advance(0)
	steps.advance(1000)
	assert_str(steps.failure).ends_with("the window saw no session: it ended (host_lost)")


func test_before_its_welcome_a_window_waits_and_a_timeout_says_so() -> void:
	var view := FakeView.new()
	view.is_welcomed = false
	var steps := _steps([_wait("phase", "lobby", 1.0)], view)
	steps.advance(0)
	steps.advance(1000)
	assert_str(steps.failure).ends_with("the window saw no Welcome yet")


func test_screen_esc_and_pointer_waits_hold_without_a_session() -> void:
	var view := EndedView.new()
	view.is_welcomed = false
	view.screen_now = "menu"
	var plan: Array[Dictionary] = [
		_wait("screen", "menu"), _wait("esc", false), _wait("pointer", false)
	]
	var steps := _steps(plan, view)
	steps.advance(0)
	assert_int(steps.status).is_equal(Steps.Status.DONE)
	# A model's wait still waits for the Welcome, and its timeout still says why.
	steps = _steps([_wait("screen", "round", 1.0), _wait("phase", "lobby", 1.0)], view)
	steps.advance(0)
	steps.advance(1000)
	assert_str(steps.failure).ends_with("the window saw screen 'menu'")
	view.screen_now = "round"
	steps = _steps([_wait("screen", "round", 1.0), _wait("phase", "lobby", 1.0)], view)
	steps.advance(2000)
	steps.advance(3000)
	assert_str(steps.failure).ends_with("the window saw no session: it ended (host_lost)")


func test_frames_lets_that_many_frames_pass() -> void:
	var press := {"line": 3, "text": "press ready", "do": "press", "action": "ready"}
	var frames := {"line": 2, "text": "frames 3", "do": "frames", "count": 3.0}
	var steps := _steps([frames, press], FakeView.new())
	for frame in 3:
		assert_dict(steps.advance(frame)).is_empty()
	assert_dict(steps.advance(3)).is_equal(press)


func test_life_and_ready_read_the_own_player_or_the_numbered_one() -> void:
	var view := FakeView.new()
	var own_downed := _wait("life", "downed")
	own_downed["player"] = 0.0
	var player_2_dead := _wait("life", "dead")
	player_2_dead["player"] = 2.0
	var steps := _steps([own_downed, player_2_dead], view)
	steps.advance(0)
	assert_int(steps.index).is_equal(0)
	view.lives[7] = "downed"
	steps.advance(10)
	assert_int(steps.index).is_equal(1)
	view.lives[9] = "dead"
	steps.advance(20)
	assert_int(steps.status).is_equal(Steps.Status.DONE)


func test_a_player_without_a_known_peer_never_matches_and_its_timeout_says_so() -> void:
	var wait := _wait("life", "alive", 1.0)
	wait["player"] = 3.0
	var steps := _steps([wait], FakeView.new())
	steps.advance(0)
	steps.advance(1000)
	assert_str(steps.failure).ends_with("the window saw no peer id for that player")


func test_an_event_matches_its_fields_with_players_by_number_and_only_once() -> void:
	var view := FakeView.new()
	var wait := _wait("event", "")
	wait["event"] = "KnockedDown"
	wait["fields"] = {"peer": 2.0}
	var again := wait.duplicate()
	var steps := _steps([wait, again], view)
	view.received.append([&"KnockedDown", {"peer": 7}])
	steps.advance(0)
	assert_int(steps.index).is_equal(0)
	view.received.append([&"KnockedDown", {"peer": 9}])
	steps.advance(10)
	# The first wait took that event; the second needs a later one.
	assert_int(steps.index).is_equal(1)
	view.received.append([&"PhaseChanged", {"phase": "round"}])
	view.received.append([&"KnockedDown", {"peer": 9}])
	steps.advance(20)
	assert_int(steps.status).is_equal(Steps.Status.DONE)


func test_an_event_field_compares_numbers_as_numbers_and_the_rest_as_text() -> void:
	var view := FakeView.new()
	var wait := _wait("event", "")
	wait["event"] = "PhaseChanged"
	wait["fields"] = {"phase": "round", "tick": 40.0}
	var steps := _steps([wait], view)
	view.received.append([&"PhaseChanged", {"phase": &"round", "tick": 41}])
	steps.advance(0)
	assert_int(steps.status).is_equal(Steps.Status.RUNNING)
	view.received.append([&"PhaseChanged", {"phase": &"round", "tick": 40}])
	steps.advance(10)
	assert_int(steps.status).is_equal(Steps.Status.DONE)


func test_the_setup_goes_once_everyone_is_in_the_roster_with_a_known_peer() -> void:
	var view := FakeView.new()
	view.roster = 2
	var setup := {
		"line": 0,
		"text": "setup",
		"do": "setup",
		"roles": {"3": "dissident"},
		"players": 3.0,
		"timeout_s": 5.0
	}
	var steps := _steps([setup], view)
	assert_dict(steps.advance(0)).is_empty()
	view.roster = 3
	assert_dict(steps.advance(10)).is_empty()
	view.peers[3] = 11
	assert_dict(steps.advance(20)).is_equal(setup)


func test_a_setup_that_never_sees_everyone_times_out() -> void:
	var setup := {"line": 0, "text": "setup", "do": "setup", "players": 3.0, "timeout_s": 1.0}
	var steps := _steps([setup], FakeView.new())
	steps.advance(0)
	steps.advance(1000)
	assert_str(steps.failure).is_equal(
		"step 1 (line 0: setup): timed out after 1.0 s; the window saw 2 of 3 players in its roster"
	)


func test_an_action_that_fails_fails_its_own_step_once() -> void:
	var press := {"line": 4, "text": "press use", "do": "press", "action": "use"}
	var steps := _steps([press, _wait("phase", "lobby")], FakeView.new())
	steps.advance(0)
	steps.fail("use has no key")
	steps.fail("a second reason")
	assert_str(steps.failure).is_equal("step 1 (line 4: press use): use has no key")
	assert_int(steps.status).is_equal(Steps.Status.FAILED)


func test_a_failure_between_actions_is_the_current_steps() -> void:
	var steps := _steps([_wait("phase", "round", 9.0)], FakeView.new())
	steps.advance(0)
	steps.fail("something set the real mouse mode")
	assert_str(steps.failure).starts_with("step 1 (line 5: wait phase round): something")


func test_each_started_step_is_reported_once() -> void:
	var started: Array[int] = []
	var steps := _steps([_wait("phase", "lobby"), _wait("phase", "round")], FakeView.new())
	steps.on_step = func(at: int, _step: Dictionary) -> void: started.append(at)
	steps.advance(0)
	steps.advance(10)
	assert_array(started).contains_exactly([0, 1])
