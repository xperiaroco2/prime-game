extends GdUnitTestSuite
## SpawnItems (ARCHITECTURE §3.3, §9.4): `knives` items of the kind on distinct random markers of
## its spawn tag, skipping the markers the task types' items took; ids in the markers' level
## order; ItemSpawned to everyone in id order, then item_rested (spawn) for each; the deal's
## events in the row's order.


func test_knives_rest_on_distinct_free_markers_of_their_tag() -> void:
	var game := FixtureDealModes.dealt(
		FixtureDealModes.deal_mode(), [1, 2, 3], {&"knives": 4, &"tasks_per_player": 3}
	)
	var markers := Array(FixtureDealModes.layouts()[FixtureDealModes.MAP].positions(&"item"))
	var knives := FixtureDealModes.items_of(game, &"knife")
	var tokens := FixtureDealModes.items_of(game, &"token")
	assert_int(knives.size()).is_equal(4)
	assert_int(tokens.size()).is_equal(9)
	var taken: Array[Vector3] = []
	for item: ItemState in tokens + knives:
		assert_array(markers).contains([item.position])
		assert_array(taken).not_contains([item.position])
		assert_int(item.where).is_equal(ItemState.Where.GROUND)
		taken.append(item.position)


func test_ids_follow_the_markers_level_order() -> void:
	var game := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), [1, 2], {&"knives": 5})
	var knives := FixtureDealModes.items_of(game, &"knife")
	for i in range(1, knives.size()):
		assert_int(knives[i].id).is_greater(knives[i - 1].id)
		# The item markers lie along x in level order.
		assert_float(knives[i].position.x).is_greater(knives[i - 1].position.x)


func test_item_spawned_goes_to_everyone_in_id_order_then_item_rested_for_each() -> void:
	var game := FixtureDealModes.dealt(
		FixtureDealModes.deal_mode(), [1, 2, 3], {&"knives": 2, &"dissidents": 1}
	)
	var knives := FixtureDealModes.items_of(game, &"knife")
	var knife_ids: Array[int] = [knives[0].id, knives[1].id]
	var spawned: Array[int] = []
	var events := game.emitted()
	var last_spawned := -1
	var first_rested := -1
	for i in events.size():
		var event := events[i].event
		if event is ItemSpawnedEvent and knife_ids.has((event as ItemSpawnedEvent).item):
			var item_spawned := event as ItemSpawnedEvent
			spawned.append(item_spawned.item)
			assert_array(Array(events[i].recipients)).is_equal([1, 2, 3])
			assert_str(item_spawned.kind).is_equal("knife")
			assert_vector(item_spawned.position).is_equal(
				game.state.items[item_spawned.item].position
			)
			assert_dict(item_spawned.to_dict()).not_contains_keys("station", "colour")
			last_spawned = i
		elif event is FixtureNoteEvent and first_rested < 0:
			if (event as FixtureNoteEvent).text == "fixture_dealt rested %d spawn" % knife_ids[0]:
				first_rested = i
	assert_array(spawned).is_equal(knife_ids)
	assert_int(first_rested).is_greater(last_spawned)
	var notes := FixtureModes.notes(game)
	assert_array(notes).contains_exactly_in_any_order(_rested_notes(game))
	assert_int(notes.find("fixture_dealt rested %d spawn" % knife_ids[1])).is_greater(
		notes.find("fixture_dealt rested %d spawn" % knife_ids[0])
	)


func test_the_deal_runs_in_the_rows_order() -> void:
	var game := FixtureDealModes.dealt(
		FixtureDealModes.deal_mode(), [1, 2], {&"knives": 1, &"dissidents": 1}
	)
	var order: Array[StringName] = []
	# Consecutive events of one name count once.
	for event_name: StringName in FixtureModes.names(game):
		if order.is_empty() or order[order.size() - 1] != event_name:
			order.append(event_name)
	(
		assert_array(order)
		. is_equal(
			[
				&"PhaseChanged",
				&"RoleAssigned",
				&"Teammates",
				&"ItemSpawned",
				&"TasksAssigned",
				&"FixtureNote",
				&"ItemSpawned",
				&"FixtureNote",
				&"PlayersPlaced",
				&"Correction",
				&"PhaseChanged",
			]
		)
	)


func test_no_knives_spawns_none() -> void:
	var game := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), [1, 2], {&"knives": 0})
	assert_array(FixtureDealModes.items_of(game, &"knife")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_too_few_free_markers_is_an_error_and_spawns_nothing() -> void:
	# 2 players x 2 tokens take 4 of 5 item markers: 1 is left for 2 knives.
	var game := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), [1, 2], {&"knives": 2}, 7, 5)
	assert_array(FixtureDealModes.items_of(game, &"knife")).is_empty()
	assert_str("\n".join(game.diagnostics)).contains("1 free item marker(s) for 2 knife item(s)")


func test_the_draw_depends_only_on_the_seed_and_its_own_purpose() -> void:
	var a := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), [1, 2, 3], {&"knives": 3}, 5)
	var b_mode := FixtureDealModes.deal_mode()
	# Another purpose for the roles draw never shifts the knives' draw (§3.3).
	(b_mode.transitions[0].actions[0] as DealRoles).rng_purpose = &"other_roles"
	var b := FixtureDealModes.dealt(b_mode, [1, 2, 3], {&"knives": 3}, 5)
	assert_array(_positions(a, &"knife")).is_equal(_positions(b, &"knife"))
	var drawn: Array[Array] = []
	for seed_value in range(1, 9):
		var game := FixtureDealModes.dealt(
			FixtureDealModes.deal_mode(), [1, 2, 3], {&"knives": 3}, seed_value
		)
		var positions := _positions(game, &"knife")
		if not drawn.has(positions):
			drawn.append(positions)
	assert_int(drawn.size()).is_greater(1)


func test_it_demands_its_count_of_markers_of_the_kinds_tag() -> void:
	var spawn := FixtureDealModes.spawn_items(FixtureDealModes.item_kind(&"knife"))
	var demands := Demands.new(null)
	spawn.add_demands({&"knives": 3}, 6, demands)
	assert_dict(demands.markers).is_equal({FixtureDealModes.ITEM_TAG: 3})
	var none := Demands.new(null)
	spawn.add_demands({&"knives": 0}, 6, none)
	assert_dict(none.markers).is_empty()


func test_the_mode_check_refuses_an_incomplete_spawn() -> void:
	var mode := FixtureDealModes.deal_mode()
	var spawn := mode.transitions[0].actions[2] as SpawnItems
	spawn.kind = FixtureDealModes.item_kind(&"spoon")
	spawn.count_setting = &""
	spawn.rng_purpose = &""
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("item kind spoon is not an item kind of the mode")
	assert_str(errors).contains("SpawnItems has no count_setting")
	assert_str(errors).contains("SpawnItems has no rng_purpose")
	spawn.kind = null
	assert_str("\n".join(ModeCheck.run(mode).errors)).contains("SpawnItems has no kind")


## The notes the fixture task type emitted for item_rested: one per spawned item, cause spawn.
func _rested_notes(game: Match) -> Array[String]:
	var found: Array[String] = []
	for id: int in game.state.items:
		found.append("fixture_dealt rested %d spawn" % id)
	return found


func _positions(game: Match, kind_id: StringName) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for item: ItemState in FixtureDealModes.items_of(game, kind_id):
		found.append(item.position)
	return found
