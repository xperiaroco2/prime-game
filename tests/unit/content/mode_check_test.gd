extends GdUnitTestSuite
## ModeCheck without layouts (ARCHITECTURE §9.1): each kind of error, found on a copy of the
## fixture mode with one thing wrong.


func test_the_fixture_mode_passes() -> void:
	var check := ModeCheck.run(FixtureModes.basic())
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


func test_an_undeclared_setting() -> void:
	var mode := FixtureModes.basic()
	var bump := FixtureBump.of(&"x")
	bump.count_setting = &"nope"
	mode.actions[0].effects.append(bump)
	_expect(mode, "count_setting names setting nope, which the mode does not declare")
	bump.count_setting = &"knives"
	_expect_none(mode)


func test_a_number_read_from_a_set_setting() -> void:
	var mode := FixtureDeliveryModes.basic()
	_expect_none(mode)
	var delivery := FixtureDeliveryModes.delivery_of(mode)
	delivery.subtasks_setting = &"banned_task_types"
	_expect(
		mode,
		"subtasks_setting names setting banned_task_types, which is a set of ids, not a whole number"
	)
	delivery.subtasks_setting = &"packages"
	_expect_none(mode)


func test_an_undeclared_side() -> void:
	var mode := FixtureModes.basic()
	mode.roles[0].side = &"pirates"
	_expect(mode, "role crew names side pirates, which the mode does not declare")
	mode = FixtureModes.basic()
	mode.win_conditions[0].side = &"pirates"
	_expect(mode, "win condition crew names side pirates")


func test_an_undeclared_first_phase_or_row_phase() -> void:
	var mode := FixtureModes.basic()
	mode.transitions[0].to = &"nowhere"
	_expect(mode, "the row lobby, all_ready goes to nowhere, which is not a phase")
	mode = FixtureModes.basic()
	mode.transitions[1].from = &"nowhere"
	_expect(mode, "a row from nowhere, which is not a phase")


func test_an_outcome_a_phase_can_report_needs_a_row() -> void:
	var mode := FixtureModes.basic()
	mode.transitions.remove_at(2)
	_expect(mode, "phase end can report back, which has no transition row")
	mode = FixtureModes.basic()
	mode.transitions.remove_at(1)
	_expect(mode, "phase round can report won, which has no transition row")
	mode = FixtureModes.basic()
	mode.actions[0].effects.append(FixtureReport.of(&"meeting_called"))
	_expect(mode, "phase round can report meeting_called, which has no transition row")


func test_a_row_for_an_outcome_its_phase_never_reports() -> void:
	var mode := FixtureModes.basic()
	mode.transitions.append(FixtureModes.row(&"lobby", &"back", &"end", []))
	_expect(mode, "the row lobby, back: phase lobby never reports back")


func test_two_rows_for_one_outcome() -> void:
	var mode := FixtureModes.basic()
	mode.transitions.append(FixtureModes.row(&"end", &"back", &"round", []))
	_expect(mode, "two rows for end, back")


func test_an_accepted_intent_nobody_handles() -> void:
	var mode := FixtureModes.basic()
	mode.phases[1].accepts.append(AcceptSpec.of(Intents.PICK_UP, AcceptSpec.From.LIVING))
	_expect(mode, "phase round accepts PickUp, which neither its class nor any rule handles")
	var knife := ItemKind.new()
	knife.id = &"knife"
	knife.spawn_tag = &"knife"
	knife.hands = 1
	knife.actions = [FixtureModes.rule(Intents.PICK_UP, [], [])]
	mode.item_kinds = [knife]
	_expect_none(mode)


func test_only_a_phase_class_takes_an_intent_from_a_newcomer() -> void:
	var mode := FixtureModes.basic()
	mode.phases[1].accepts.append(AcceptSpec.of(Intents.USE, AcceptSpec.From.NEWCOMER))
	_expect(mode, "phase round accepts Use from a newcomer, which its class does not handle")


func test_a_tick_system_or_task_type_outcome_needs_a_row() -> void:
	var mode := FixtureModes.basic()
	var type := mode.task_types[0] as FixtureTaskType
	type.reports = [&"sabotaged"]
	_expect(mode, "phase lobby can report sabotaged, which has no transition row")
	_expect(mode, "phase round can report sabotaged, which has no transition row")
	type.reports = []
	var system := TickSystemReporting.new()
	mode.phases[1].tick_systems = [system]
	_expect(mode, "phase round can report overtime, which has no transition row")
	mode.transitions.append(FixtureModes.row(&"round", &"overtime", &"end", []))
	_expect_none(mode)


func test_a_phase_needs_the_level_it_plays_on() -> void:
	var mode := FixtureModes.basic()
	mode.lobby_level = ""
	_expect(mode, "phase lobby plays in the lobby, but lobby_level is empty")
	mode = FixtureModes.basic()
	mode.maps = PackedStringArray()
	_expect(mode, "phase round plays on the map, but the mode has no maps")


func test_an_unknown_intent_or_a_sender_nobody_matches() -> void:
	var mode := FixtureModes.basic()
	mode.phases[1].accepts.append(AcceptSpec.of(&"Hit", AcceptSpec.From.LIVING))
	_expect(mode, "phase round accepts Hit, which is no intent")
	mode = FixtureModes.basic()
	mode.phases[1].accepts[0].from = 0
	_expect(mode, "phase round accepts Use from nobody")


func test_the_ghosts_retired_sender_bit_is_refused() -> void:
	# A mode written for ghosts (MoveClaim from LIVING | 8) would otherwise silently stop
	# accepting the downed's claims: 8 is never reused (vision revision 1, M4-1).
	var mode := FixtureModes.basic()
	mode.phases[1].accepts[1].from = AcceptSpec.From.LIVING | 8
	var text := "phase round accepts MoveClaim from bits 8, which name no sender"
	_expect(mode, text + " (8 was the ghosts', retired)")
	mode = FixtureModes.basic()
	mode.phases[1].accepts[1].from = AcceptSpec.From.LIVING | 64
	# Only bit 8 is named as the ghosts': another stray bit gets no hint.
	var errors := Array(ModeCheck.run(mode).errors)
	assert_array(errors).contains(
		["mode.phases[1]: phase round accepts MoveClaim from bits 64, which name no sender"]
	)
	mode = FixtureModes.basic()
	# Every player flag is fine (a newcomer's intent is a phase class's, which MoveClaim is not).
	mode.phases[1].accepts[1].from = AcceptSpec.ALL_FROM & ~AcceptSpec.From.NEWCOMER
	_expect_none(mode)


func test_rules_with_wrong_or_repeated_triggers() -> void:
	var mode := FixtureModes.basic()
	mode.actions.append(FixtureModes.rule(Intents.USE, [], []))
	_expect(mode, "mode.actions: two rules on Use")
	mode = FixtureModes.basic()
	mode.reactions = [FixtureModes.rule(Intents.USE, [], [])]
	_expect(mode, "mode.reactions: trigger Use is not one of")
	mode = FixtureModes.basic()
	mode.actions = [FixtureModes.rule(Facts.ITEM_RESTED, [], [])]
	_expect(mode, "mode.actions: trigger item_rested is not one of")


func test_a_negated_cost() -> void:
	var mode := FixtureModes.basic()
	var cost := FixtureCost.of(&"uses", 1)
	cost.negate = true
	mode.actions[0].conditions = [cost]
	_expect(mode, "mode.actions: rule Use negates a cost")


func test_a_reaction_holding_a_cost_that_reads_the_actor_is_refused() -> void:
	# A reaction runs for no player (actor 0, which has no PlayerState), so a Cooldown or a
	# StaminaCost always refuses there and the reaction would silently never run (#283; the
	# runtime refusal: tests/unit/combat/costs_in_reactions_test.gd).
	var costs: Array[Cost] = [
		FixtureCombatModes.cooldown(&"hit", FixtureCombatModes.COOLDOWN_S),
		FixtureCombatModes.stamina_cost(FixtureCombatModes.STAMINA_COST),
	]
	for cost: Cost in costs:
		var mode := _reacting_on_the_clock([FixtureCost.of(&"uses", 1), cost])
		var cost_class := (cost.get_script() as Script).get_global_name()
		var error := (
			(
				"mode.reactions[1]: the reaction on clock_ended of the mode holds the cost %s,"
				+ " which reads the actor's player state: a reaction runs for no player (actor 0),"
				+ " so the cost always refuses and the reaction never runs"
			)
			% cost_class
		)
		assert_array(Array(ModeCheck.run(mode).errors)).contains_exactly([error])
		# Match refuses the mode, as for every ModeCheck error.
		var game := FixtureModes.create(mode)
		assert_array(Array(game.refusals)).contains([error])
		assert_bool(game.start(0)).is_false()
		assert_array(game.emitted()).is_empty()


func test_the_refused_reaction_names_the_modes_file_and_each_cost() -> void:
	var cooldown := FixtureCombatModes.cooldown(&"hit", FixtureCombatModes.COOLDOWN_S)
	var stamina := FixtureCombatModes.stamina_cost(FixtureCombatModes.STAMINA_COST)
	var mode := _reacting_on_the_clock([cooldown, stamina])
	mode.resource_path = "res://tests/fixtures/match/reacting_mode.tres"
	var errors := ModeCheck.run(mode).errors
	assert_array(Array(errors)).has_size(2)
	var where := "the reaction on clock_ended of mode res://tests/fixtures/match/reacting_mode.tres"
	assert_str(errors[0]).contains(where + " holds the cost Cooldown,")
	assert_str(errors[1]).contains(where + " holds the cost StaminaCost,")


func test_a_negated_cost_in_a_reaction_is_reported_once() -> void:
	# A negated Cooldown passes for actor 0 and is never paid (Rule.costs skips it), so the reaction
	# would run: only the "negates a cost" error applies, not the never-runs one.
	var cooldown := FixtureCombatModes.cooldown(&"hit", FixtureCombatModes.COOLDOWN_S)
	cooldown.negate = true
	var mode := _reacting_on_the_clock([cooldown])
	assert_array(Array(ModeCheck.run(mode).errors)).contains_exactly(
		["mode.reactions: rule clock_ended negates a cost"]
	)


func test_a_reaction_may_hold_a_cost_that_reads_no_player_state() -> void:
	# FixtureCost reads only MatchState's counters, which have a row for peer 0 too.
	_expect_none(_reacting_on_the_clock([FixtureCost.of(&"uses", 1)]))
	# The costs refused in a reaction are fine in an action: the knife's Use holds both.
	_expect_none(FixtureCombatModes.basic())


func test_every_cost_in_core_reads_the_actors_player_state() -> void:
	# The costs of core/ and whether a reaction may hold them (Cost.reads_actor_state). A new cost
	# in core/ fails this test until it is listed here and in ARCHITECTURE §9.2.
	var expected: Dictionary[StringName, bool] = {&"Cooldown": true, &"StaminaCost": true}
	var found: Dictionary[StringName, bool] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var path: String = entry["path"]
		var class_id: StringName = entry["class"]
		if path.begins_with("res://core/") and class_id != &"Cost" and _extends_cost(class_id):
			var script := load(path) as GDScript
			var cost := script.new() as Cost
			found[class_id] = cost.reads_actor_state()
	assert_dict(found).is_equal(expected)
	# The base class's default: a cost that does not say reads the actor.
	assert_bool(Cost.new().reads_actor_state()).is_true()


func test_numbers_out_of_bounds() -> void:
	var mode := FixtureModes.basic()
	mode.player_rules.health = 0
	_expect(mode, "health is 0, outside 1 to 1000")
	mode = FixtureModes.basic()
	mode.settings[0].default_value = 11
	_expect(mode, "setting knives default_value is 11, outside 0 to 10")
	mode = FixtureModes.basic()
	mode.phases[2].settings[&"go_after_ticks"] = 5000.0
	_expect(mode, "phase end: go_after_ticks is 5000, outside 0 to 1000")
	mode = FixtureModes.basic()
	mode.phases[2].settings[&"typo"] = 1.0
	_expect(mode, "phase end: unknown setting typo")


func test_an_item_kind_takes_one_or_two_hands_which_the_data_sets() -> void:
	# Vision revision 1, Two hands: the neutral default (0) is out of bounds, so a forgotten
	# `hands` is refused (#58).
	for hands: int in [0, 3]:
		var mode := FixtureItemModes.basic()
		mode.find_item_kind(&"tool").hands = hands
		_expect(mode, "item kind tool hands is %d, outside 1 to 2" % hands)
	for hands: int in [1, 2]:
		var mode := FixtureItemModes.basic()
		mode.find_item_kind(&"tool").hands = hands
		_expect_none(mode)
	assert_int(ItemKind.new().hands).is_equal(0)


func test_a_task_type_needs_a_description() -> void:
	# The task screen shows it (vision revision 1, the Tab task screen).
	for empty: String in ["", "  \n"]:
		var mode := FixtureModes.basic()
		(mode.task_types[0] as TaskType).description = empty
		_expect(mode, "task type fixture_task has no description")
	assert_str(TaskType.new().description).is_empty()


func test_repeated_ids() -> void:
	var mode := FixtureModes.basic()
	mode.roles.append(FixtureModes.role(&"crew", &"crew", false))
	_expect(mode, "two roles with the id crew")


func test_empty_entries_and_missing_parts() -> void:
	var mode := FixtureModes.basic()
	mode.actions.append(null)
	_expect(mode, "mode.actions has an empty entry")
	mode = FixtureModes.basic()
	mode.reactions.append(null)
	_expect(mode, "mode.reactions has an empty entry")
	mode = FixtureModes.basic()
	mode.first_phase = &""
	_expect(mode, "first_phase  is not a phase of the mode")
	mode = FixtureModes.basic()
	mode.phases[0].phase_class = GameMode
	_expect(mode, "phase lobby: phase_class is not a script extending Phase")
	mode = FixtureModes.basic()
	mode.player_rules = null
	_expect(mode, "the mode has no player_rules")


func test_ids_outside_the_wires_alphabet() -> void:
	# D1 (a), the designer's answer on #96: every content id is 1 to 32 characters of a-z, 0-9
	# and _, because ids travel on the wire as the content's names (§4.3, E5).
	var mode := FixtureItemModes.basic()
	mode.roles[0].id = &"Crew"
	mode.settings[0].id = StringName("k".repeat(33))
	mode.item_kinds[0].spawn_tag = &"package-spot"
	(mode.transitions[0].actions[0] as PlacePlayers).tag = &"round player"
	mode.phases[2].id = &""
	mode.actions[0].conditions.append(ReasonCondition.new())
	_expect(mode, 'roles[0].id is "Crew": an id is 1 to 32 characters of a-z, 0-9 and _')
	_expect(mode, 'settings[0].id is "%s"' % "k".repeat(33))
	_expect(mode, 'item_kinds[0].spawn_tag is "package-spot"')
	_expect(mode, 'actions[0].tag is "round player"')
	_expect(mode, 'phases[2].id is ""')
	_expect(mode, 'conditions[3]\'s rejection reason is "Too far"')


func test_ids_of_32_characters_of_the_alphabet_pass() -> void:
	var mode := FixtureItemModes.basic()
	mode.roles[0].id = StringName("crew_0123456789_abcdefghijklmnop")
	assert_int(String(mode.roles[0].id).length()).is_equal(32)
	_expect_none(mode)
	assert_bool(ModeCheck.is_wire_id("a")).is_true()
	for bad: String in ["", "A", "a-b", "a b", "é", "a.b", "x".repeat(33)]:
		assert_bool(ModeCheck.is_wire_id(bad)).override_failure_message(bad).is_false()


func test_a_role_owned_public_event_is_a_warning_not_an_error() -> void:
	var mode := FixtureModes.basic()
	mode.roles[1].actions = [FixtureModes.rule(Intents.USE, [], [FixtureNote.of("seen")])]
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).has_size(1)
	var private_note := FixtureNote.of("private")
	private_note.to_actor = true
	mode.roles[1].actions = [FixtureModes.rule(Intents.USE, [], [private_note])]
	# The note's class could go to everyone, so the check still warns: it looks at the class.
	assert_array(Array(ModeCheck.run(mode).warnings)).has_size(1)
	mode.roles[1].actions = [FixtureModes.rule(Intents.USE, [], [FixtureModes.place(&"x")])]
	assert_array(Array(ModeCheck.run(mode).warnings)).has_size(1)
	mode.roles[1].actions = [FixtureModes.rule(Intents.USE, [], [FixtureBump.of(&"x")])]
	assert_array(Array(ModeCheck.run(mode).warnings)).is_empty()


func test_a_phase_that_can_knock_down_must_list_life_ticks() -> void:
	# The combat fixture's Round accepts Use, and the knife's Use rule strikes: with its LifeTicks
	# it passes; without, a downed player would never die.
	var mode := FixtureCombatModes.basic()
	_expect_none(mode)
	mode.find_phase(&"round").tick_systems = []
	_expect(mode, 'phase round runs [&"Use"], which can knock a player down')
	_expect(mode, "lists no LifeTicks")
	# A phase that cannot knock anyone down needs none: the plain fixture's Use only notes.
	var plain := FixtureModes.basic()
	plain.find_phase(&"round").tick_systems = []
	_expect_none(plain)


func test_a_phase_that_starts_a_channel_must_list_channel_ticks() -> void:
	# The raise of FixtureCombatModes.raising() is a channel: without ChannelTicks it would never
	# complete, and the knockdown it paused would never run on.
	var mode := FixtureCombatModes.raising()
	_expect_none(mode)
	var round_spec := mode.find_phase(&"round")
	round_spec.tick_systems = [round_spec.tick_systems[0]]
	_expect(mode, 'phase round accepts [&"Raise"], which starts a channel')
	_expect(mode, "lists no ChannelTicks")


func test_the_raise_parts_check_their_numbers() -> void:
	var mode := FixtureCombatModes.raising()
	mode.actions[2] = FixtureCombatModes.raise_rule(0.0, 0.0, 0)
	_expect(mode, "RaiseDowned seconds is 0, outside 0.05 to 600")
	_expect(mode, "TargetInReach reach_m is 0, outside 0.1 to 10")
	_expect(mode, "RaiseDowned revive_health is 0, outside 1 to 100")
	mode.actions[2] = FixtureCombatModes.raise_rule(3.0, 2.0, 101)
	_expect(mode, "RaiseDowned revive_health is 101, outside 1 to 100")
	mode.actions[2] = FixtureCombatModes.raise_rule(3.0, 2.0, 100)
	_expect_none(mode)


func test_a_raise_without_target_downed_is_refused() -> void:
	var mode := FixtureCombatModes.raising()
	# TargetDowned is the raise rule's first condition.
	mode.actions[2].conditions.remove_at(0)
	_expect(mode, "rule Raise starts a channel that requires the condition TargetDowned")


func test_a_channel_outside_an_action_is_refused() -> void:
	var mode := FixtureCombatModes.raising()
	var raise := FixtureCombatModes.raise_rule()
	var reaction := FixtureModes.rule(Facts.ITEM_RESTED, [TargetDowned.new()], raise.effects)
	mode.reactions = [reaction]
	_expect(mode, "mode.reactions: rule item_rested starts a channel")
	mode.reactions = []
	mode.transitions[1].actions.append(raise.effects[0])
	_expect(mode, "row round, won starts a channel")


func test_a_role_gated_action_in_a_mode_with_a_channel_is_a_warning() -> void:
	# Applying it stops the actor's raise publicly; a refusal does not: the stop reveals the role.
	var mode := FixtureCombatModes.raising()
	mode.roles[1].actions = [FixtureModes.rule(Intents.PICK_UP, [], [])]
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).has_size(1)
	assert_str(check.warnings[0]).contains("in a mode with a channel")
	# The same role action in a mode with no channel says nothing.
	var plain := FixtureCombatModes.respawning()
	plain.roles[1].actions = [FixtureModes.rule(Intents.PICK_UP, [], [])]
	assert_array(Array(ModeCheck.run(plain).warnings)).is_empty()


func test_a_respawn_needs_its_tag_and_rng_purpose() -> void:
	var mode := FixtureCombatModes.respawning()
	_expect_none(mode)
	FixtureCombatModes.life_ticks(mode).respawn = Respawn.new()
	_expect(mode, "Respawn has no tag")
	_expect(mode, "Respawn has no rng_purpose")


func _expect(mode: GameMode, fragment: String) -> void:
	var errors := ModeCheck.run(mode).errors
	var found := false
	for error: String in errors:
		found = found or error.contains(fragment)
	(
		assert_bool(found)
		. override_failure_message("no error contains '%s' in %s" % [fragment, errors])
		. is_true()
	)


func _expect_none(mode: GameMode) -> void:
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


## FixtureModes.basic() with two reactions: one on item_rested that holds nothing, then one on
## clock_ended (reactions[1]) that holds `conditions` and notes "reacted".
func _reacting_on_the_clock(conditions: Array[Condition]) -> GameMode:
	var mode := FixtureModes.basic()
	var note: Array[RuleEffect] = [FixtureNote.of("reacted")]
	mode.reactions = [
		FixtureModes.rule(Facts.ITEM_RESTED, [], []),
		FixtureModes.rule(Facts.CLOCK_ENDED, conditions, note),
	]
	return mode


## Whether the global class `class_id` is Cost or extends it.
static func _extends_cost(class_id: StringName) -> bool:
	var current := class_id
	while not current.is_empty():
		if current == &"Cost":
			return true
		current = _global_base(current)
	return false


static func _global_base(class_id: StringName) -> StringName:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry["class"] == class_id:
			return entry["base"]
	return &""


## A tick system that declares the outcome `overtime`.
class TickSystemReporting:
	extends TickSystem

	func reported_outcomes() -> Array[StringName]:
		return [&"overtime"]


## A condition that rejects with a reason outside the wire's alphabet.
class ReasonCondition:
	extends Condition

	func _reason() -> StringName:
		return &"Too far"
