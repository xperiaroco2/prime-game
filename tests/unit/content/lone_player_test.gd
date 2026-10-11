extends GdUnitTestSuite
## A lone player in the base mode (#719, the engineer's answer: min_players stays 1, so one
## player may start a match alone to try the mechanics, and that player is always an engineer).
## The base mode's own data (`content/modes/base_mode.tres`, ARCHITECTURE §9.5.1): its DealRoles
## quota leaves at least 1 player to Crew, so one player is dealt Crew whatever the seed and the
## `dissidents` setting; and the round with that one player plays: no win condition fires at
## once (the crew is present, the packages wait), Delivery deals its task, and delivering every
## package wins it for the crew. A content test (§9.6): it loads `content/` and `levels/`.

const BASE_MODE := "res://content/modes/base_mode.tres"
const LONE := 1
## Seeds the deal runs with: the quota's count does not depend on the draw, so these stand for
## every seed.
const SEEDS := 32


func test_the_base_mode_s_dissident_quota_leaves_one_player_to_crew() -> void:
	var mode := _base_mode()
	var deal := mode.find_transition(&"loading", LoadingPhase.ALL_LOADED).actions[0] as DealRoles
	assert_object(deal).is_not_null()
	assert_str(deal.default_role.id).is_equal("crew")
	assert_int(deal.quotas.size()).is_equal(1)
	assert_str(deal.quotas[0].role.id).is_equal("dissident")
	assert_int(deal.quotas[0].leave_at_least).is_equal(1)
	assert_int(mode.min_players).is_equal(1)


func test_a_lone_player_is_dealt_crew_whatever_the_seed_and_the_dissidents_setting() -> void:
	var mode := _base_mode()
	var layouts := _layouts_for(mode)
	var most := mode.find_setting(&"dissidents").max_value
	for seed_value in SEEDS:
		for wanted: int in [1, most]:
			var game := _lone_in_pregame(mode, layouts, seed_value, wanted)
			var context := "seed %d, %d dissidents set" % [seed_value, wanted]
			assert_str(game.state.player(LONE).role).override_failure_message(context).is_equal(
				"crew"
			)
			var told := game.view_of(LONE).events_named(&"RoleAssigned")
			assert_int(told.size()).override_failure_message(context).is_equal(1)
			(
				assert_str((told[0] as RoleAssignedEvent).role)
				. override_failure_message(context)
				. is_equal("crew")
			)
			(
				assert_array(game.view_of(LONE).events_named(&"Teammates"))
				. override_failure_message(context)
				. is_empty()
			)
			assert_array(Array(game.diagnostics)).override_failure_message(context).is_empty()


func test_the_lone_engineer_s_round_plays_and_ends_when_every_package_is_delivered() -> void:
	var mode := _base_mode()
	var game := _lone_in_pregame(mode, _layouts_for(mode), 7, 1)
	FixtureModes.run_ticks(game, 3 * Ticks.RATE + 1)
	assert_str(game.phase_id()).is_equal("round")
	# Delivery dealt its one shared task: 6 packages for 6 circles (the default `packages`), and
	# the 2 knives lie on the map.
	assert_int(game.state.tasks.size()).is_equal(1)
	assert_int(game.state.stations.size()).is_equal(6)
	assert_int(FixtureDealModes.items_of(game, &"package").size()).is_equal(6)
	assert_int(FixtureDealModes.items_of(game, &"knife").size()).is_equal(2)
	# A minute of the round alone: the crew is present, no package is delivered and the clock
	# runs, so no win condition fires.
	FixtureWinModes.run_through(game, game.ticked_through() + 60 * Ticks.RATE)
	assert_str(game.phase_id()).is_equal("round")
	assert_str(game.state.winner).is_empty()
	assert_array(game.view_of(LONE).events_named(&"MatchEnded")).is_empty()
	assert_int(game.state.clock_ticks_left).is_equal(9 * 60 * Ticks.RATE)
	# The engineer delivers every package alone: the crew wins.
	var task := FixtureDeliveryModes.task_of(game)
	for index in 6:
		var package := FixtureDeliveryModes.package_of(game, task, index)
		var circle := FixtureDeliveryModes.circle_of(game, task, index)
		FixtureDeliveryModes.carry_to(game, LONE, package, circle.position)
	assert_str(game.phase_id()).is_equal("end")
	assert_str(game.state.winner).is_equal("crew")
	var ended := game.view_of(LONE).events_named(&"MatchEnded")
	assert_int(ended.size()).is_equal(1)
	assert_str(ended[0].to_dict()["reason"]).is_equal("every_task_done")
	assert_array(Array(game.diagnostics)).is_empty()


## A base mode match with `seed_value` that the lone player joins; the host (that player) sets
## `dissidents` in the lobby, gets ready and loads: the match is in the pregame, the deal done.
func _lone_in_pregame(
	mode: GameMode, layouts: Dictionary[String, LevelLayout], seed_value: int, dissidents: int
) -> Match:
	var game := Match.new(mode, seed_value, FlatWorldQuery.new(), layouts)
	game.keep_history = true
	game.start(0)
	FixtureBaseMode.join(game, LONE)
	var settings := {"dissidents": dissidents}
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, LONE, {"settings": settings})
	assert_array(FixtureModes.rejections(game, LONE)).is_empty()
	assert_int(game.state.settings[&"dissidents"]).is_equal(dissidents)
	FixtureBaseMode.ready(game, LONE)
	for i in 1000:
		if game.phase_id() == &"loading":
			break
		FixtureModes.run_ticks(game, 1)
	FixtureBaseMode.load_ack(game, LONE)
	assert_str(game.phase_id()).is_equal("pregame")
	return game


func _layouts_for(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var levels := MarkerReader.read_levels(mode, FlatWorldQuery.new())
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts


func _base_mode() -> GameMode:
	return load(BASE_MODE) as GameMode
