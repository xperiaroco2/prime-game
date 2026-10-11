extends GdUnitTestSuite
## Interact naming an item and display stations (the cooking ADR's CE1, CE6, #770; ARCHITECTURE
## §4.1, §9.2): an Interact names exactly one of a station and an item, else `bad_args`; one naming
## an item runs only that item's kind's target_actions, never the hand item's, the role's or the
## mode's, so an unknown item or one whose kind has none is refused `nothing_to_do`; one naming a
## station of a display kind is refused `nothing_to_do` before the station kind's, the role's and
## the mode's rules, so a forged one never reaches the mode's Interact rule. Driven by commands on
## a seeded FixtureGiveModes match whose mode also holds a mode-level Interact rule (a note).

const P1 := 1
const P2 := 2
const UNKNOWN := 99
## Inside station 1's cylinder (FixtureStationModes: station 1 at (0, 0, 20), radius 1 m).
const NEAR_PANEL := Vector3(0, 0, 19.1)


func test_an_item_whose_kind_has_no_target_actions_never_reaches_the_modes_rule() -> void:
	var game := FixtureGiveModes.in_round([P1, P2], _with_mode_rule())
	var bun := FixtureGiveModes.lay_bun(game, FixtureGiveModes.BOX_AT, 0)
	FixtureGiveModes.interact_item(game, P1, bun.id)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do"])
	assert_array(FixtureModes.notes(game)).is_empty()


func test_an_unknown_item_is_nothing_to_do() -> void:
	var game := FixtureGiveModes.in_round([P1, P2], _with_mode_rule())
	FixtureGiveModes.interact_item(game, P1, UNKNOWN)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do"])
	assert_array(FixtureModes.notes(game)).is_empty()


func test_naming_both_or_neither_is_bad_args() -> void:
	var game := FixtureGiveModes.in_round([P1, P2], _with_mode_rule())
	var box := FixtureGiveModes.box_of(game)
	FixtureModes.send(game, Intents.INTERACT, P1, {"station": 1, "item": box.id}, 1)
	FixtureModes.send(game, Intents.INTERACT, P1, {"station": -1, "item": -1}, 2)
	FixtureModes.send(game, Intents.INTERACT, P1, {}, 3)
	assert_array(FixtureModes.rejections(game, P1)).is_equal(
		[&"bad_args", &"bad_args", &"bad_args"]
	)
	assert_array(FixtureModes.notes(game)).is_empty()
	assert_array(FixtureGiveModes.ids_of(game, &"bun")).is_empty()


func test_the_box_runs_its_own_rule_and_not_the_modes() -> void:
	var game := FixtureGiveModes.in_round([P1, P2], _with_mode_rule())
	FixtureGiveModes.interact_item(game, P1, FixtureGiveModes.box_of(game).id)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(FixtureGiveModes.ids_of(game, &"bun")).has_size(1)
	assert_array(FixtureModes.notes(game)).is_empty()


func test_an_interact_rule_on_the_hand_item_changes_nothing() -> void:
	# ModeCheck refuses an item kind's Interact rule (GE2), so a match would not start with it: it
	# goes in after the start, as a Match that skipped the check would see it.
	var mode := _with_mode_rule()
	var game := FixtureGiveModes.in_round([P1, P2], mode)
	var tool := mode.find_item_kind(&"tool")
	tool.actions.append(FixtureModes.rule(Intents.INTERACT, [], [FixtureNote.of("tool")]))
	var held := FixtureItemModes.lay(game, &"tool", FixtureGiveModes.HERE)
	FixtureItemModes.pick_up(game, P1, held)
	assert_int(game.state.player(P1).held_item).is_equal(held.id)
	var bun := FixtureGiveModes.lay_bun(game, FixtureGiveModes.BOX_AT, 0)
	FixtureGiveModes.interact_item(game, P1, bun.id)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do"])
	assert_array(FixtureModes.notes(game)).is_empty()


func test_a_display_station_is_nothing_to_do_and_never_reaches_the_modes_rule() -> void:
	var mode := _with_mode_rule()
	var panel := FixtureStationModes.type_of(mode).panel
	panel.display = true
	panel.actions = []
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
	var game := FixtureGiveModes.in_round([P1, P2], mode)
	assert_bool(game.state.stations.has(1)).is_true()
	FixtureItemModes.stand(game, P1, NEAR_PANEL)
	FixtureStationModes.interact(game, P1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do"])
	assert_array(FixtureModes.notes(game)).is_empty()


func test_the_same_station_not_a_display_reaches_the_modes_rule() -> void:
	var mode := _with_mode_rule()
	var panel := FixtureStationModes.type_of(mode).panel
	panel.actions = []
	var game := FixtureGiveModes.in_round([P1, P2], mode)
	FixtureItemModes.stand(game, P1, NEAR_PANEL)
	FixtureStationModes.interact(game, P1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(FixtureModes.notes(game)).is_equal(["mode"])


## FixtureGiveModes.basic() with a mode-level Interact rule that emits the note "mode".
func _with_mode_rule() -> GameMode:
	var mode := FixtureGiveModes.basic()
	mode.actions.append(FixtureModes.rule(Intents.INTERACT, [], [FixtureNote.of("mode")]))
	return mode
