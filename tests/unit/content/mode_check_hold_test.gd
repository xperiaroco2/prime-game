extends GdUnitTestSuite
## ModeCheck on HoldStation (the car repair ADR's RE3 and RE9, #805; ARCHITECTURE §9.1, §9.4.2):
## its rule holds AtStation, StationInSight and ChannelFree (after the two), it runs only on an
## intent that names a station, a timed hold has seconds in bounds and an endless one has none, and
## a role-gated hold whose type's hold_emits() reaches everyone warns that it reveals the role. Each
## found on FixtureStationModes.holding() with one thing wrong.

const PANEL := "station kind panel.actions"


func test_the_holding_fixtures_pass() -> void:
	for effect: HoldStation in [
		FixtureStationModes.hold(1.0),
		FixtureStationModes.hold(0.0, true),
		FixtureStationModes.hold(0.0, true, false)
	]:
		var check := ModeCheck.run(FixtureStationModes.holding(effect))
		assert_array(Array(check.errors)).is_empty()
		assert_array(Array(check.warnings)).is_empty()


func test_a_hold_needs_at_station_and_channel_free() -> void:
	for missing: Script in [AtStation, ChannelFree]:
		var mode := FixtureStationModes.holding(FixtureStationModes.hold(1.0))
		var rule := _panel(mode).actions[0]
		var kept: Array[Condition] = []
		for condition: Condition in rule.conditions:
			if condition.get_script() != missing:
				kept.append(condition)
		rule.conditions = kept
		if missing == AtStation:
			# StationUsable's own check finds AtStation missing before it too.
			assert_str(" ".join(ModeCheck.run(mode).errors)).contains(
				"%s: rule Interact starts a channel that requires the condition AtStation" % PANEL
			)
		else:
			_expect(
				mode,
				"%s: rule Interact starts a channel that requires the condition ChannelFree" % PANEL
			)


func test_a_hold_on_an_intent_naming_no_station_is_refused() -> void:
	var mode := FixtureStationModes.holding(FixtureStationModes.hold(1.0))
	var rule := FixtureStationModes.hold_rule(FixtureStationModes.hold(1.0))
	rule.trigger = Intents.USE
	mode.actions.append(rule)
	assert_str(" ".join(ModeCheck.run(mode).errors)).contains(
		"mode.actions: rule Use holds a station, which only an intent naming one"
	)


func test_a_timed_hold_needs_its_seconds_and_an_endless_one_has_none() -> void:
	_expect(FixtureStationModes.holding(FixtureStationModes.hold(0.0)), "HoldStation seconds is 0")
	_expect(
		FixtureStationModes.holding(FixtureStationModes.hold(2.0, true)),
		"HoldStation is endless and has seconds 2"
	)


func test_a_role_gated_hold_whose_hooks_reach_everyone_warns() -> void:
	var mode := FixtureStationModes.holding(FixtureStationModes.hold(0.0, true))
	_panel(mode).actions[0].conditions.push_front(FixtureRoleGate.new())
	var reveal := (
		"%s: rule Interact is role-owned or role-gated and emits an event to everyone" % PANEL
	)
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_str(" ".join(check.warnings)).contains(reveal)
	# The control: the warning comes from the type's hold_emits(), which HoldStation's emits()
	# lacks; the warning about a channel stays.
	FixtureStationModes.type_of(mode).quiet = true
	var quiet := ModeCheck.run(mode)
	assert_str(" ".join(quiet.warnings)).not_contains(reveal)
	assert_str(" ".join(quiet.warnings)).contains("in a mode with a channel")


func test_a_phase_accepting_interact_that_holds_lists_channel_ticks() -> void:
	var mode := FixtureStationModes.holding(FixtureStationModes.hold(1.0))
	var round_spec := mode.find_phase(&"round")
	var kept: Array[TickSystem] = []
	for system: TickSystem in round_spec.tick_systems:
		if not system is ChannelTicks:
			kept.append(system)
	round_spec.tick_systems = kept
	# The fixture's Raise starts a channel too: the error names Interact only for the hold.
	(
		assert_str(" ".join(ModeCheck.run(mode).errors))
		. contains(
			'phase round accepts [&"Raise", &"Interact"], which starts a channel, but lists no ChannelTicks'
		)
	)


func test_a_hold_needs_station_in_sight() -> void:
	var mode := FixtureStationModes.holding(FixtureStationModes.hold(1.0))
	_drop(_panel(mode).actions[0], StationInSight)
	var errors := " ".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("%s: rule Interact holds a station without StationInSight" % PANEL)
	assert_str(errors).contains("holds ChannelFree without StationInSight before it")


func test_channel_free_comes_after_at_station_and_station_in_sight() -> void:
	# ChannelFree's busy would tell a player anywhere that another holds the station (§9.4.1).
	for earlier: Script in [AtStation, StationInSight]:
		var mode := FixtureStationModes.holding(FixtureStationModes.hold(1.0))
		var rule := _panel(mode).actions[0]
		var moved: Condition = null
		for condition: Condition in rule.conditions:
			if condition.get_script() == earlier:
				moved = condition
		rule.conditions.erase(moved)
		rule.conditions.append(moved)
		# StationUsable, now before the moved condition, finds it missing too: so not _expect.
		assert_str(" ".join(ModeCheck.run(mode).errors)).contains(
			(
				"%s: rule Interact holds ChannelFree without %s before it"
				% [PANEL, earlier.get_global_name()]
			)
		)


func _drop(rule: Rule, missing: Script) -> void:
	var kept: Array[Condition] = []
	for condition: Condition in rule.conditions:
		if condition.get_script() != missing:
			kept.append(condition)
	rule.conditions = kept


func _panel(mode: GameMode) -> StationKind:
	return FixtureStationModes.type_of(mode).panel


func _expect(mode: GameMode, fragment: String) -> void:
	var errors := ModeCheck.run(mode).errors
	assert_array(Array(errors)).has_size(1)
	assert_str(" ".join(errors)).contains(fragment)
