extends GdUnitTestSuite
## The steps of a playcheck window (tools/playcheck/playcheck_steps.gd, #186): waits that pass at
## once or time out at their timeout and not before, frames, actions, the host's setup and event
## matching through player numbers, over a fake View and a fake clock (no window, no sleep); what
## the window draws (`wait text`, `wait shown`) and the `button` step's choice (#275); the `aim`
## step, the item it picks and the turn that makes a real PlayerController face it (#276); the
## window turning every frame until `aim off` is covered by the items scenario. The plan comes
## from tools/runner/playcheck.py (its parser: tools/runner/tests/test_playcheck.py).

const Steps := preload("res://tools/playcheck/playcheck_steps.gd")
const PLAYER_SCENE := preload("res://client/player/player.tscn")


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
	## What each field holds; one missing is "" and hidden.
	var texts: Dictionary[String, String] = {}
	var hidden: Array[String] = []

	func field_text(field: String) -> String:
		return texts.get(field, "")

	func field_shown(field: String) -> bool:
		return texts.has(field) and not hidden.has(field)

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


func _text(field: String, op: String, value: String, timeout_s := 2.0) -> Dictionary:
	return {
		"line": 9,
		"text": "wait text %s %s %s" % [field, op, value],
		"do": "wait",
		"what": "text",
		"field": field,
		"op": op,
		"value": value,
		"timeout_s": timeout_s
	}


func _shown(field: String, on: bool, timeout_s := 2.0) -> Dictionary:
	return {
		"line": 9,
		"text": "wait shown %s %s" % [field, "on" if on else "off"],
		"do": "wait",
		"what": "shown",
		"field": field,
		"value": on,
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


func test_text_is_has_and_lacks_hold_on_what_the_window_draws() -> void:
	var view := FakeView.new()
	view.texts["hud.hand"] = "Hand: Knife"
	var plan: Array[Dictionary] = [
		_text("hud.hand", "is", "Hand: Knife"),
		_text("hud.hand", "has", "Knife"),
		_text("hud.hand", "lacks", "empty"),
	]
	var steps := _steps(plan, view)
	steps.advance(0)
	assert_int(steps.status).is_equal(Steps.Status.DONE)


func test_text_is_times_out_naming_the_field_and_the_text_the_window_had() -> void:
	var view := FakeView.new()
	view.texts["hud.hand"] = "Hand: empty"
	var steps := _steps([_text("hud.hand", "is", "Hand: Knife", 1.0)], view)
	steps.advance(0)
	steps.advance(999)
	assert_int(steps.status).is_equal(Steps.Status.RUNNING)
	steps.advance(1000)
	assert_str(steps.failure).is_equal(
		(
			"step 1 (line 9: wait text hud.hand is Hand: Knife): timed out after 1.0 s; the window"
			+ " saw hud.hand 'Hand: empty'"
		)
	)


func test_text_has_and_lacks_time_out_and_then_hold_when_the_text_changes() -> void:
	var view := FakeView.new()
	view.texts["esc.tabs"] = "Resume, Lobby, Leave, Quit"
	for wait: Dictionary in [
		_text("esc.tabs", "has", "Voice", 1.0), _text("esc.tabs", "lacks", "Lobby", 1.0)
	]:
		var failing := _steps([wait], view)
		failing.advance(0)
		failing.advance(1000)
		assert_str(failing.failure).ends_with(
			"the window saw esc.tabs 'Resume, Lobby, Leave, Quit'"
		)
	view.texts["esc.tabs"] = "Resume, Voice, Leave, Quit"
	var steps := _steps(
		[_text("esc.tabs", "has", "Voice", 1.0), _text("esc.tabs", "lacks", "Lobby", 1.0)], view
	)
	steps.advance(0)
	assert_int(steps.status).is_equal(Steps.Status.DONE)


func test_text_collapses_each_run_of_whitespace_to_one_space() -> void:
	var view := FakeView.new()
	view.texts["lobby.roster"] = " Ann (host, you)  ready\nBo  not\tready "
	var plan: Array[Dictionary] = [
		_text("lobby.roster", "is", "Ann (host, you) ready Bo not ready"),
		_text("lobby.roster", "has", "(host, you) ready"),
		_text("lobby.roster", "has", "ready  Bo"),
		_text("lobby.roster", "lacks", "you)  not"),
	]
	var steps := _steps(plan, view)
	steps.advance(0)
	assert_int(steps.status).is_equal(Steps.Status.DONE)
	assert_str(Steps.collapse("  a \n\n b\t c  ")).is_equal("a b c")


func test_a_hidden_field_reads_as_empty() -> void:
	var view := FakeView.new()
	view.texts["life.title"] = "Dead"
	view.hidden.append("life.title")
	var steps := _steps([_text("life.title", "lacks", "Dead")], view)
	steps.advance(0)
	assert_int(steps.status).is_equal(Steps.Status.DONE)
	steps = _steps([_text("life.title", "has", "Dead", 1.0)], view)
	steps.advance(0)
	steps.advance(1000)
	assert_str(steps.failure).ends_with("the window saw life.title ''")
	assert_str(steps.drawn("life.title")).is_empty()
	view.hidden.clear()
	assert_str(steps.drawn("life.title")).is_equal("Dead")


func test_shown_on_and_off_hold_and_time_out_naming_what_the_window_showed() -> void:
	var view := FakeView.new()
	view.texts["hud.crosshair"] = "+"
	var steps := _steps([_shown("hud.crosshair", true), _shown("hud.health", false)], view)
	steps.advance(0)
	assert_int(steps.status).is_equal(Steps.Status.DONE)
	steps = _steps([_shown("hud.crosshair", false, 1.0)], view)
	steps.advance(0)
	steps.advance(1000)
	assert_str(steps.failure).is_equal(
		(
			"step 1 (line 9: wait shown hud.crosshair off): timed out after 1.0 s; the window saw"
			+ " hud.crosshair shown"
		)
	)
	steps = _steps([_shown("hud.health", true, 1.0)], view)
	steps.advance(0)
	steps.advance(1000)
	assert_str(steps.failure).ends_with("the window saw hud.health hidden")
	view.hidden.append("hud.crosshair")
	steps = _steps([_shown("hud.crosshair", false)], view)
	steps.advance(0)
	assert_int(steps.status).is_equal(Steps.Status.DONE)


func test_text_and_shown_read_the_window_without_a_session() -> void:
	var view := EndedView.new()
	view.is_welcomed = false
	view.texts["end.winner"] = "The match is over"
	var steps := _steps([_text("end.winner", "has", "over"), _shown("end.winner", true)], view)
	steps.advance(0)
	assert_int(steps.status).is_equal(Steps.Status.DONE)


func test_a_button_step_is_an_action_the_window_performs() -> void:
	var button := {"line": 7, "text": "button Resume", "do": "button", "label": "Resume"}
	var steps := _steps([button], FakeView.new())
	assert_dict(steps.advance(0)).is_equal(button)
	steps.fail(Steps.button_problem([], "Resume"))
	assert_str(steps.failure).is_equal(
		"step 1 (line 7: button Resume): no visible button 'Resume'; the window shows []"
	)


func test_a_button_is_the_one_visible_enabled_button_with_that_text() -> void:
	var ui := auto_free(VBoxContainer.new()) as VBoxContainer
	add_child(ui)
	var hidden_box := VBoxContainer.new()
	hidden_box.visible = false
	ui.add_child(hidden_box)
	for made: Array in [
		[ui, "Resume", false],
		[hidden_box, "Lobby", false],
		[ui, "Leave", true],
		[ui, "Yes", false],
		[ui, "Yes", false],
		[ui, "Back  to\nlobby", false],
	]:
		var each := Button.new()
		each.text = str(made[1])
		each.disabled = made[2]
		(made[0] as Node).add_child(each)
	var buttons := Steps.visible_buttons(ui)
	assert_int(buttons.size()).is_equal(4)
	assert_str(Steps.button_problem(buttons, "Resume")).is_empty()
	assert_str(Steps.buttons_named(buttons, "Resume")[0].text).is_equal("Resume")
	assert_str(Steps.button_problem(buttons, "Back to lobby")).is_empty()
	assert_str(Steps.button_problem(buttons, "Yes")).is_equal("2 buttons 'Yes'")
	var shows := "the window shows ['Resume', 'Yes', 'Yes', 'Back to lobby']"
	# Hidden (in a hidden parent) or disabled: not a button the step may press.
	assert_str(Steps.button_problem(buttons, "Lobby")).is_equal(
		"no visible button 'Lobby'; " + shows
	)
	assert_str(Steps.button_problem(buttons, "Leave")).is_equal(
		"no visible button 'Leave'; " + shows
	)
	assert_str(Steps.button_problem(buttons, "Resum")).starts_with("no visible button 'Resum';")


func test_aim_item_and_aim_off_are_action_steps_advance_returns() -> void:
	var aim := {"line": 4, "text": "aim item knife", "do": "aim", "kind": "knife"}
	var off := {"line": 6, "text": "aim off", "do": "aim", "kind": ""}
	var steps := _steps([aim, _frames(1), off], FakeView.new())
	assert_dict(steps.advance(0)).is_equal(aim)
	assert_dict(steps.advance(16)).is_empty()
	assert_dict(steps.advance(32)).is_equal(off)
	assert_dict(steps.advance(48)).is_empty()
	assert_int(steps.status).is_equal(Steps.Status.DONE)


func test_the_aim_picks_the_nearest_resting_item_of_its_kind() -> void:
	var model := ClientModel.new(GameMode.new())
	model.items[1] = _item(&"knife", Vector3(5, 0, 0))
	model.items[2] = _item(&"knife", Vector3(0, 0, 3), 7)
	model.items[3] = _item(&"package", Vector3(1, 0, 0))
	model.items[4] = _item(&"knife", Vector3(0, 0, -4))
	assert_int(Steps.nearest_resting(model, &"knife", Vector3.ZERO)).is_equal(4)
	assert_int(Steps.nearest_resting(model, &"package", Vector3.ZERO)).is_equal(3)
	assert_int(Steps.nearest_resting(model, &"knife", Vector3(4, 0, 0))).is_equal(1)
	# Held (item 2, by peer 7) or delivered: never one to face.
	model.items[1].delivered = true
	model.items[4].holder = 7
	assert_int(Steps.nearest_resting(model, &"knife", Vector3.ZERO)).is_equal(-1)
	assert_int(Steps.nearest_resting(model, &"crowbar", Vector3.ZERO)).is_equal(-1)
	# In flight (§7.1.16): its position is only the launch's origin.
	model.items[3].flying = true
	assert_int(Steps.nearest_resting(model, &"package", Vector3.ZERO)).is_equal(-1)


func test_the_aim_turn_makes_the_player_look_at_the_target() -> void:
	var player := auto_free(PLAYER_SCENE.instantiate()) as PlayerController
	add_child(player)
	player.global_position = Vector3(2, 0, -1)
	player.look(0.7, -0.2)
	for target: Vector3 in [
		Vector3(6, 0.1, -1),
		Vector3(-3, 0.1, 4),
		Vector3(2.5, 0.1, -1.2),
		Vector3(1, 2.5, -9),
		Vector3(2, 0.1, 3),
	]:
		var eye := player.get_camera().global_position
		var turn := Steps.aim_turn(player.look_vector(), eye, target)
		# The shorter way round: never more than half a turn.
		assert_float(absf(turn.x)).is_less_equal(PI)
		player.look(turn.x, turn.y)
		var wanted := (target - eye).normalized()
		assert_float(player.look_vector().distance_to(wanted)).is_less(0.001)


func test_the_aim_turn_keeps_the_yaw_straight_above_or_at_the_eye() -> void:
	var ahead := Vector3(0, 0, -1)
	assert_vector(Steps.aim_turn(ahead, Vector3.ZERO, Vector3.ZERO)).is_equal(Vector2.ZERO)
	var below := Steps.aim_turn(ahead, Vector3(0, 1.6, 0), Vector3(0, 0, 0))
	assert_float(below.x).is_equal(0.0)
	assert_float(below.y).is_equal_approx(-PI / 2.0, 0.0001)
	# A quarter turn to the right (to +X) is a negative yaw; level, no pitch.
	var right := Steps.aim_turn(ahead, Vector3.ZERO, Vector3(3, 0, 0))
	assert_float(right.x).is_equal_approx(-PI / 2.0, 0.0001)
	assert_float(right.y).is_equal_approx(0.0, 0.0001)


func _item(kind: StringName, at: Vector3, holder := ClientModel.NO_HOLDER) -> ClientModel.Item:
	var item := ClientModel.Item.new()
	item.kind = kind
	item.position = at
	item.holder = holder
	return item


func _frames(count: int) -> Dictionary:
	return {"line": 5, "text": "frames %d" % count, "do": "frames", "count": count}
