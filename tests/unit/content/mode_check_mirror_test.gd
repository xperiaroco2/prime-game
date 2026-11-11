extends GdUnitTestSuite
## The mode check on the mirror's parts (ARCHITECTURE §9.4, §7.1.24; #1394): the conditions a
## place's Interact rule must hold, UseMirror only on a station kind's Interact rule, at most
## Mirror.MAX_PLACES players (the wire's cap), MirrorTicks.problems (a phase that places the mirror
## lists MirrorTicks, a row out of it runs EndMirror); and LayoutCheck's at least one `mirror`
## marker (StationTicks with `every_marker`).


func test_the_fixture_mode_and_layouts_pass() -> void:
	assert_array(Array(ModeCheck.run(FixtureMirror.mode()).errors)).is_empty()
	var found := LayoutCheck.run(FixtureMirror.mode(), FixtureMirror.layouts())
	assert_array(Array(found)).is_empty()


func test_a_place_rule_without_each_required_condition_is_refused() -> void:
	for required: Script in UseMirror.required_conditions():
		var made := FixtureMirror.mode()
		var rule := _place_rule(made)
		rule.conditions.assign(
			rule.conditions.filter(func(c: Condition) -> bool: return c.get_script() != required)
		)
		_expect(made, "requires the condition %s" % required.get_global_name())


func test_use_mirror_outside_a_station_kinds_interact_rule_is_refused() -> void:
	var made := FixtureMirror.mode()
	made.actions.append(
		FixtureModes.rule(Intents.INTERACT, [] as Array[Condition], [UseMirror.new()])
	)
	_expect(made, "UseMirror is only for a station kind's rule on Interact")


func test_more_players_than_the_wire_tells_places_is_refused() -> void:
	var made := FixtureMirror.mode()
	made.max_players = Mirror.MAX_PLACES + 1
	_expect(made, "the mirror tells at most %d places" % Mirror.MAX_PLACES)


func test_a_phase_placing_the_mirror_without_mirror_ticks_is_refused() -> void:
	var made := FixtureMirror.mode()
	var lobby := made.find_phase(&"lobby")
	lobby.tick_systems.assign(
		lobby.tick_systems.filter(func(s: TickSystem) -> bool: return s is not MirrorTicks)
	)
	_expect(made, "phase lobby places the mirror but lists no MirrorTicks")


func test_a_row_out_of_the_mirror_without_end_mirror_is_refused() -> void:
	var made := FixtureMirror.mode()
	for row: Transition in made.transitions:
		row.actions.assign(
			row.actions.filter(func(a: RuleEffect) -> bool: return a is not EndMirror)
		)
	_expect(made, "runs no EndMirror: a mirror place would outlast it")


func test_a_lobby_without_a_mirror_marker_names_mirror() -> void:
	var missing := FixtureMirror.layouts()
	missing[FixtureBaseMode.LOBBY] = FixtureBaseMode.layouts()[FixtureBaseMode.LOBBY]
	_expect_layout(missing, "mirror")


func _place_rule(made: GameMode) -> Rule:
	for kind: StationKind in Stations.kinds_in(made):
		if kind.id == &"mirror":
			return kind.actions[0]
	return null


func _expect(mode: GameMode, fragment: String) -> void:
	_expect_in(Array(ModeCheck.run(mode).errors), fragment)


func _expect_layout(layouts: Dictionary[String, LevelLayout], fragment: String) -> void:
	_expect_in(Array(LayoutCheck.run(FixtureMirror.mode(), layouts)), fragment)


func _expect_in(errors: Array, fragment: String) -> void:
	var found := false
	for error: String in errors:
		found = found or error.contains(fragment)
	(
		assert_bool(found)
		. override_failure_message("no error contains '%s' in %s" % [fragment, errors])
		. is_true()
	)
