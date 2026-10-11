extends GdUnitTestSuite
## ModeCheck on item targets, GiveItem and display stations (the cooking ADR's CE1 to CE3, CE6,
## #770; ARCHITECTURE §9.2): an item kind's target_actions trigger only on an intent that names a
## target and hold no station part (UseStation, AtStation, StationInSight, StationUsable); a
## GiveItem runs only on such an intent (never a reaction, another intent or a row) and gives a
## one-handed, capped kind; max_items is 0 or 1 to MatchState.MAX_ITEM_ID; a display station kind
## holds no actions; an accepted Interact that only target_actions handle counts as handled. Each
## found on FixtureGiveModes with one thing wrong.

const BOX := "item kind box.target_actions"


func test_the_give_fixture_passes() -> void:
	var check := ModeCheck.run(FixtureGiveModes.basic())
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


func test_an_interact_only_target_actions_handle_counts_as_handled() -> void:
	var mode := FixtureGiveModes.basic()
	FixtureStationModes.type_of(mode).panel.actions = []
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


func test_a_target_action_triggers_only_on_an_intent_naming_a_target() -> void:
	var mode := FixtureGiveModes.basic()
	_box(mode).target_actions.append(FixtureModes.rule(Intents.USE, [], [FixtureNote.of("box")]))
	_expect(mode, '%s: trigger Use is not one of [&"Interact"]' % BOX)


func test_a_station_part_in_a_target_action_is_refused() -> void:
	var parts: Array[Object] = [
		UseStation.new(), AtStation.new(), StationInSight.new(), StationUsable.new()
	]
	for part: Object in parts:
		var mode := FixtureGiveModes.basic()
		var take := _box(mode).target_actions[0]
		if part is Condition:
			take.conditions.append(part as Condition)
		else:
			take.effects.append(part as RuleEffect)
		var name := (part.get_script() as Script).get_global_name()
		_expect(
			mode,
			(
				"%s: rule Interact holds %s, which finds a station, and an intent naming an item"
				% [BOX, name]
			)
		)


func test_a_give_item_in_a_reaction_or_on_another_intent_is_refused() -> void:
	var on_use := FixtureGiveModes.basic()
	on_use.actions.append(FixtureModes.rule(Intents.USE, [], [_give(on_use)]))
	_expect(on_use, "mode.actions: rule Use gives an item at the rule's target")
	var reaction := FixtureGiveModes.basic()
	reaction.reactions.append(FixtureModes.rule(Facts.ITEM_RESTED, [], [_give(reaction)]))
	_expect(reaction, "rule item_rested gives an item at the rule's target")


func test_a_give_item_in_a_row_is_refused() -> void:
	var mode := FixtureGiveModes.basic()
	mode.find_transition(&"lobby", &"all_ready").actions.append(_give(mode))
	_expect(
		mode, "row lobby, all_ready gives an item, which only a player's intent naming a target"
	)


func test_a_give_item_needs_a_one_handed_capped_kind() -> void:
	var two_handed := FixtureGiveModes.basic()
	_given(two_handed).hands = 2
	_expect(two_handed, "GiveItem gives item kind bun, which is two-handed")
	var uncapped := FixtureGiveModes.basic()
	_given(uncapped).max_items = 0
	_expect(uncapped, "GiveItem gives item kind bun, which sets no max_items")
	var none := FixtureGiveModes.basic()
	(_box(none).target_actions[0].effects[0] as GiveItem).kind = null
	_expect(none, "GiveItem has no kind")


func test_max_items_is_bounded() -> void:
	for bad: int in [-1, MatchState.MAX_ITEM_ID + 1]:
		var mode := FixtureGiveModes.basic()
		_given(mode).max_items = bad
		_expect(mode, "item kind bun max_items")
	var at_bound := FixtureGiveModes.basic()
	_given(at_bound).max_items = MatchState.MAX_ITEM_ID
	assert_array(Array(ModeCheck.run(at_bound).errors)).is_empty()


func test_a_display_station_kind_with_actions_is_refused() -> void:
	var mode := FixtureGiveModes.basic()
	FixtureStationModes.type_of(mode).panel.display = true
	_expect(mode, "station kind panel is a display kind and holds actions, which never run")


func _box(mode: GameMode) -> ItemKind:
	return mode.find_item_kind(&"box")


func _given(mode: GameMode) -> ItemKind:
	return mode.find_item_kind(&"bun")


func _give(mode: GameMode) -> GiveItem:
	var give := GiveItem.new()
	give.kind = _given(mode)
	return give


## ModeCheck finds an error containing `text`, and Match refuses to start the mode.
func _expect(mode: GameMode, text: String) -> void:
	var errors := Array(ModeCheck.run(mode).errors)
	assert_str(" | ".join(errors)).contains(text)
	assert_bool(FixtureModes.create(mode).start(0)).is_false()
