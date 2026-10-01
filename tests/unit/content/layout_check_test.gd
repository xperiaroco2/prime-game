extends GdUnitTestSuite
## LayoutCheck (ARCHITECTURE §9.1, the mode check with layouts), which Match runs on creation: a
## level without a layout, a spawn tag a row places on and a level lacks, a marker with two tags,
## and a lobby with fewer lobby_player markers than the mode's maximum of players.


func test_the_fixture_layouts_fit() -> void:
	var found := LayoutCheck.run(FixtureBaseMode.mode(), FixtureBaseMode.layouts())
	assert_array(Array(found)).is_empty()


func test_a_level_without_a_layout() -> void:
	var layouts := FixtureBaseMode.layouts()
	layouts.erase(FixtureBaseMode.LOBBY)
	layouts.erase(FixtureBaseMode.SMALL_MAP)
	(
		assert_array(Array(LayoutCheck.run(FixtureBaseMode.mode(), layouts)))
		. is_equal(
			[
				"no layout for the lobby fixture://lobby",
				"no layout for the map fixture://small_map",
			]
		)
	)


func test_a_tag_a_row_places_on_that_a_map_lacks() -> void:
	var layouts := FixtureBaseMode.layouts()
	var small := LevelLayout.new(FixtureBaseMode.SMALL_MAP)
	small.add_marker(&"round_player", Vector3.ZERO)
	small.add_marker(&"circle", Vector3.ONE)
	layouts[FixtureBaseMode.SMALL_MAP] = small
	assert_array(Array(LayoutCheck.run(FixtureBaseMode.mode(), layouts))).is_equal(
		["fixture://small_map has no knife marker, which the row loading, all_loaded places on"]
	)


func test_a_marker_with_two_tags() -> void:
	var layouts := FixtureBaseMode.layouts()
	var map := layouts[FixtureBaseMode.MAP]
	map.add_marker(&"knife", map.positions(&"circle")[0])
	assert_array(Array(LayoutCheck.run(FixtureBaseMode.mode(), layouts))).is_equal(
		["fixture://map has a marker at (30.0, 0.0, 0.0) with two tags, circle and knife"]
	)


func test_a_lobby_with_fewer_player_markers_than_the_maximum() -> void:
	var layouts := FixtureBaseMode.layouts()
	var lobby := LevelLayout.new(FixtureBaseMode.LOBBY)
	for i in FixtureBaseMode.MAX_PLAYERS - 1:
		lobby.add_marker(LayoutCheck.LOBBY_PLAYER, Vector3(i, 0, 0))
	layouts[FixtureBaseMode.LOBBY] = lobby
	assert_array(Array(LayoutCheck.run(FixtureBaseMode.mode(), layouts))).is_equal(
		["the lobby fixture://lobby has 3 lobby_player marker(s), fewer than the mode's 4 players"]
	)


func test_match_refuses_a_mode_whose_layouts_do_not_fit() -> void:
	var layouts := FixtureBaseMode.layouts()
	layouts.erase(FixtureBaseMode.MAP)
	var game := Match.new(FixtureBaseMode.mode(), 7, FlatWorldQuery.new(), layouts)
	assert_array(Array(game.refusals)).is_equal(["no layout for the map fixture://map"])
	assert_bool(game.start(0)).is_false()


func test_demands_sum_the_rows_into_the_level() -> void:
	var mode := FixtureBaseMode.mode()
	var demands := LayoutCheck.demands_of(
		mode, PhaseSpec.Level.MAP, {&"knives": 3, &"circles": 2}, 3
	)
	assert_dict(demands.markers).is_equal({&"round_player": 3, &"knife": 3, &"circle": 2})
	assert_dict(demands.colours).is_equal({&"circle": 2})
	var lobby := LayoutCheck.demands_of(mode, PhaseSpec.Level.LOBBY, {}, 3)
	assert_dict(lobby.markers).is_equal({&"lobby_player": 3})


# DealTasks forwards its demand to the mode's task types (§9.4, 2c): the fit check sees their
# markers, and a map without them is refused.
func test_a_task_types_demand_reaches_the_fit_check() -> void:
	var mode := _mode_with_a_token_task()
	var demands := LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, mode.default_settings(), 3)
	# One shared task of 3 coins, whatever the players.
	assert_int(demands.markers.get(&"coin", 0)).is_equal(3)
	assert_array(Array(LayoutCheck.run(mode, FixtureDealModes.layouts()))).is_equal(
		["fixture://deal_map has no coin marker, which the row lobby, all_ready places on"]
	)


func test_deliverys_circles_and_packages_reach_the_fit_check() -> void:
	# The real task type through DealTasks: Delivery's demand arrives only if the Demands carry
	# the mode (LayoutCheck builds them with it).
	var mode := FixtureDeliveryModes.basic(4)
	var demands := LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, mode.default_settings(), 3)
	# One shared task of 4 packages: a circle, a package and a colour per package.
	assert_int(demands.markers.get(&"circle", 0)).is_equal(4)
	assert_int(demands.markers.get(&"package", 0)).is_equal(4)
	assert_dict(demands.colours).is_equal({&"circle": 4})
	var map := FixtureModes.MAP
	(
		assert_array(Array(LayoutCheck.run(mode, FixtureModes.layouts())))
		. is_equal(
			[
				"%s has no circle marker, which the row lobby, all_ready places on" % map,
				"%s has no package marker, which the row lobby, all_ready places on" % map,
			]
		)
	)
	assert_array(Array(LayoutCheck.run(mode, FixtureDeliveryModes.layouts()))).is_empty()


func test_a_respawn_demands_a_respawn_marker_on_every_map_and_the_fit_check_shows_it() -> void:
	var mode := FixtureCombatModes.respawning()
	var demands := LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, mode.default_settings(), 3)
	assert_int(demands.markers.get(FixtureModes.RESPAWN_TAG, 0)).is_equal(1)
	var lobby := LayoutCheck.demands_of(mode, PhaseSpec.Level.LOBBY, mode.default_settings(), 3)
	assert_bool(lobby.markers.has(FixtureModes.RESPAWN_TAG)).is_false()
	var layouts := FixtureModes.layouts()
	assert_array(Array(LayoutCheck.run(mode, layouts))).is_empty()
	assert_array(Array(demands.shortfalls(layouts[FixtureModes.MAP]))).is_empty()
	var bare := LevelLayout.new(FixtureModes.MAP)
	for i in 4:
		bare.add_marker(&"round_player", Vector3(10 + i, 0, 5))
	layouts[FixtureModes.MAP] = bare
	assert_array(Array(LayoutCheck.run(mode, layouts))).is_equal(
		[
			(
				"%s has no respawn marker, which a tick system of phase round places on"
				% FixtureModes.MAP
			)
		]
	)
	assert_array(Array(demands.shortfalls(bare))).is_equal(
		["1 respawn marker(s) needed, the map has 0"]
	)
	# Without a Respawn, LifeTicks demands nothing.
	assert_array(Array(LayoutCheck.run(FixtureCombatModes.basic(), layouts))).is_empty()


func test_a_respawn_in_two_phases_on_the_map_demands_its_marker_once() -> void:
	# The phases' tick systems share the map's markers: the most of any one phase, not the sum.
	var mode := FixtureCombatModes.respawning()
	var overtime := mode.find_phase(&"round").duplicate() as PhaseSpec
	overtime.id = &"overtime"
	mode.phases.append(overtime)
	var demands := LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, mode.default_settings(), 3)
	assert_int(demands.markers.get(FixtureModes.RESPAWN_TAG, 0)).is_equal(1)


func _mode_with_a_token_task() -> GameMode:
	var token := ItemKind.new()
	token.id = &"coin"
	token.display_name = "Coin"
	token.spawn_tag = &"coin"
	var mode := FixtureDealModes.deal_mode([FixtureDealtTaskType.new(&"fixture_dealt", token, 3)])
	mode.item_kinds.append(token)
	return mode
