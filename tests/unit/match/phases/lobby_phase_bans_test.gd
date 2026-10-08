extends GdUnitTestSuite
## The host's bans of task types in the Lobby (ARCHITECTURE §4.1, §9.4; the engineer's decision of
## 2026-09-30, #79): ChangeSettings with a set of task type ids, checked against the mode's task
## types and against `tasks` (DealTasks.settings_problem), all or nothing, shown in
## SettingsChanged; the fit check over any draw of the types left; the deal never draws a banned
## type. Two fake task types (FixtureBanModes): `first` needs 2 tokens, `second` 4.

const P1 := 1
const P2 := 2
const BANNED := &"banned_task_types"


func test_settings_changed_shows_no_ban_and_the_largest_demand_by_default() -> void:
	var game := FixtureBanModes.started()
	FixtureBaseMode.join(game, P1)
	var changed := FixtureBanModes.last_change(game, P1)
	assert_dict(changed.id_sets).is_equal({BANNED: PackedStringArray()})
	# One task of either type: the map must hold the larger, `second`'s 4 tokens.
	assert_int(changed.needed_markers[FixtureBanModes.TOKEN_TAG]).is_equal(4)
	assert_int(changed.map_markers[FixtureBanModes.TOKEN_TAG]).is_equal(5)
	assert_dict(changed.to_dict()["id_sets"] as Dictionary).is_equal({BANNED: PackedStringArray()})


func test_the_host_bans_a_task_type_and_everyone_sees_it() -> void:
	var game := FixtureBanModes.started()
	FixtureBaseMode.join(game, P1)
	FixtureBaseMode.join(game, P2)
	FixtureBanModes.change(game, {"banned_task_types": ["second"]})
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(Array(game.state.id_sets[BANNED])).is_equal(["second"])
	for peer: int in [P1, P2]:
		var changed := FixtureBanModes.last_change(game, peer)
		assert_dict(changed.id_sets).is_equal({BANNED: PackedStringArray(["second"])})
		# Only `first` is left: 2 tokens.
		assert_int(changed.needed_markers[FixtureBanModes.TOKEN_TAG]).is_equal(2)
	# Lifted: the empty set again.
	FixtureBanModes.change(game, {"banned_task_types": []})
	assert_dict(FixtureBanModes.last_change(game, P2).id_sets).is_equal(
		{BANNED: PackedStringArray()}
	)


func test_a_ban_is_a_set_in_the_modes_order() -> void:
	var game := FixtureBanModes.started()
	FixtureBaseMode.join(game, P1)
	FixtureBanModes.change(game, {"banned_task_types": [&"first", "first"]})
	assert_array(Array(game.state.id_sets[BANNED])).is_equal(["first"])


func test_a_ban_leaving_fewer_types_than_tasks_is_refused_whole() -> void:
	var game := FixtureBanModes.started()
	FixtureBaseMode.join(game, P1)
	FixtureBanModes.change(game, {"tasks": 2})
	assert_int(game.state.settings[&"tasks"]).is_equal(2)
	FixtureBanModes.change(game, {"banned_task_types": ["second"], "knives": 1}, 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_bounds"])
	assert_bool(game.state.id_sets.has(BANNED)).is_false()
	assert_int(game.state.settings[&"knives"]).is_equal(2)
	# Lowering `tasks` in the same change makes the ban fit.
	FixtureBanModes.change(game, {"banned_task_types": ["second"], "tasks": 1}, 6)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_bounds"])
	assert_array(Array(game.state.id_sets[BANNED])).is_equal(["second"])
	# And `tasks` above the types left is refused while the ban stands.
	FixtureBanModes.change(game, {"tasks": 2}, 7)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_bounds", &"out_of_bounds"])
	assert_int(game.state.settings[&"tasks"]).is_equal(1)


func test_banning_every_task_type_is_refused() -> void:
	var game := FixtureBanModes.started()
	FixtureBaseMode.join(game, P1)
	FixtureBanModes.change(game, {"banned_task_types": ["second", "first"]})
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_bounds"])
	assert_bool(game.state.id_sets.has(BANNED)).is_false()


func test_a_bad_ban_is_rejected_whole() -> void:
	var game := FixtureBanModes.started()
	FixtureBaseMode.join(game, P1)
	var bad: Array[Dictionary] = [
		{"banned_task_types": "second", "knives": 1},
		{"banned_task_types": [5]},
		{"banned_task_types": 1},
		{"knives": ["first"]},
		{"banned_task_types": ["third"], "knives": 1},
	]
	for changes: Dictionary in bad:
		FixtureBanModes.change(game, changes)
	(
		assert_array(FixtureModes.rejections(game, P1))
		. is_equal(
			[
				&"unknown_setting",
				&"unknown_setting",
				&"unknown_setting",
				&"unknown_setting",
				&"out_of_bounds",
			]
		)
	)
	assert_dict(game.state.id_sets).is_empty()
	assert_int(game.state.settings[&"knives"]).is_equal(2)


func test_the_fit_check_holds_for_any_draw() -> void:
	var game := FixtureBanModes.started()
	FixtureBaseMode.join(game, P1)
	# Two tasks: both types, 6 tokens, and the map has 5.
	FixtureBanModes.change(game, {"tasks": 2})
	FixtureBaseMode.ready(game, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_array(Array(FixtureBanModes.last_change(game, P1).shortfalls)).is_equal(
		["6 token marker(s) needed, the map has 5"]
	)
	# The small map has 1 token marker: even `first` alone does not fit there.
	FixtureModes.send(
		game,
		Intents.CHANGE_SETTINGS,
		P1,
		{
			"settings": {"tasks": 1, "banned_task_types": ["second"]},
			"map": FixtureBaseMode.SMALL_MAP
		}
	)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_array(Array(FixtureBanModes.last_change(game, P1).shortfalls)).contains(
		["2 token marker(s) needed, the map has 1"]
	)
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, {"map": FixtureBaseMode.MAP}, 3)
	assert_str(game.phase_id()).is_equal("countdown")


func test_the_deal_never_draws_a_banned_type() -> void:
	for seed_value in range(1, 11):
		var game := FixtureBanModes.started(seed_value)
		FixtureBaseMode.join(game, P1)
		FixtureBanModes.change(game, {"banned_task_types": ["first"]})
		FixtureBaseMode.ready(game, P1)
		FixtureModes.run_ticks(game, 101)
		FixtureBaseMode.load_ack(game, P1)
		FixtureBaseMode.through_pregame(game)
		assert_str(game.phase_id()).is_equal("round")
		assert_int(game.state.tasks.size()).is_equal(1)
		for id: int in game.state.tasks:
			assert_str(game.state.tasks[id].type.id).is_equal("second")
		assert_array(Array(game.diagnostics)).is_empty()


func test_the_bans_outlive_the_match() -> void:
	var game := FixtureBanModes.started()
	FixtureBaseMode.join(game, P1)
	FixtureBanModes.change(game, {"banned_task_types": ["first"]})
	_play_to_the_round(game)
	# The crew wins, and the host goes back: ResetMatch keeps the settings, the bans among them.
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_array(Array(game.state.id_sets[BANNED])).is_equal(["first"])
	# The next match's deal still leaves `first` out.
	_play_to_the_round(game)
	assert_int(game.state.tasks.size()).is_equal(1)
	for id: int in game.state.tasks:
		assert_str(game.state.tasks[id].type.id).is_equal("second")
	assert_array(Array(game.diagnostics)).is_empty()


## P1 readies, the countdown runs out, P1 loads and the pregame runs out: the round.
func _play_to_the_round(game: Match) -> void:
	FixtureBaseMode.ready(game, P1)
	FixtureModes.run_ticks(game, 101)
	FixtureBaseMode.load_ack(game, P1)
	FixtureBaseMode.through_pregame(game)
	assert_str(game.phase_id()).is_equal("round")
