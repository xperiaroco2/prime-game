extends GdUnitTestSuite
## The base mode's deal as data (ARCHITECTURE §3.2, §9.5; 2c): the `Loading, all_loaded -> Round`
## row's actions in order with their settings, and the Crew, Dissident and Knife entries. It
## loads `content/`, like the mode check beside it (§9.6); the parts' behaviour is tested in
## tests/unit/deal/ with modes built in code.

const BASE_MODE := "res://content/modes/base_mode.tres"


func test_the_deal_runs_roles_tasks_knives_then_placement() -> void:
	var mode := load(BASE_MODE) as GameMode
	var row := mode.find_transition(&"loading", &"all_loaded")
	assert_str(row.to).is_equal("round")
	# StartClock (2h) comes last, after PlacePlayers.
	assert_int(row.actions.size()).is_greater_equal(4)
	var roles := row.actions[0] as DealRoles
	assert_object(roles).is_not_null()
	assert_int(roles.quotas.size()).is_equal(1)
	assert_str(roles.quotas[0].role.id).is_equal("dissident")
	assert_str(roles.quotas[0].count_setting).is_equal("dissidents")
	assert_int(roles.quotas[0].leave_at_least).is_equal(1)
	assert_str(roles.default_role.id).is_equal("crew")
	assert_str(roles.rng_purpose).is_equal("roles")
	var tasks := row.actions[1] as DealTasks
	assert_object(tasks).is_not_null()
	assert_str(tasks.tasks_setting).is_equal("tasks_per_player")
	var knives := row.actions[2] as SpawnItems
	assert_object(knives).is_not_null()
	assert_str(knives.kind.id).is_equal("knife")
	assert_str(knives.count_setting).is_equal("knives")
	assert_str(knives.rng_purpose).is_equal("knives")
	var place := row.actions[3] as PlacePlayers
	assert_object(place).is_not_null()
	assert_str(place.tag).is_equal("round_player")


func test_crew_and_dissident() -> void:
	var mode := load(BASE_MODE) as GameMode
	var crew := mode.find_role(&"crew")
	assert_str(crew.display_name).is_equal("Crew")
	assert_str(crew.side).is_equal("crew")
	assert_bool(crew.knows_teammates).is_false()
	assert_array(crew.actions).is_empty()
	var dissident := mode.find_role(&"dissident")
	assert_str(dissident.display_name).is_equal("Dissident")
	assert_str(dissident.side).is_equal("dissidents")
	assert_bool(dissident.knows_teammates).is_true()
	assert_array(dissident.actions).is_empty()


func test_knife() -> void:
	var mode := load(BASE_MODE) as GameMode
	var knife := mode.find_item_kind(&"knife")
	assert_str(knife.display_name).is_equal("Knife")
	assert_str(knife.spawn_tag).is_equal("knife")
	# The knife's Use rule is 2g's (#63).
	assert_array(knife.actions).is_empty()


func test_the_deal_demands_knife_markers_at_the_default_settings() -> void:
	var mode := load(BASE_MODE) as GameMode
	var demands := Demands.new(mode)
	for action: RuleEffect in mode.find_transition(&"loading", &"all_loaded").actions:
		action.add_demands(mode.default_settings(), 10, demands)
	assert_int(demands.markers.get(&"knife", 0)).is_equal(2)
	assert_int(demands.markers.get(&"round_player", 0)).is_equal(10)
