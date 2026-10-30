extends GdUnitTestSuite
## BotScenario and its steps and targets (ARCHITECTURE §9.7): data only; problems() says what
## makes a scenario unplayable before a runner starts it. A mode built in code (§9.6).


func test_a_complete_scenario_has_no_problems() -> void:
	var scenario := _scenario()
	assert_array(Array(scenario.problems())).is_empty()
	assert_int(scenario.steps_of(1).size()).is_equal(2)
	assert_array(scenario.steps_of(2)).is_empty()
	assert_array(scenario.steps_of(0)).is_empty()


func test_the_setup_is_checked_against_the_mode() -> void:
	var scenario := _scenario()
	scenario.bots = FixtureBaseMode.MAX_PLAYERS + 1
	scenario.map = "res://nowhere.tscn"
	scenario.forced_roles = {1: &"medic", 99: &"crew"}
	scenario.settings = {&"speed": 3}
	scenario.expected_ends = [&"aliens"]
	scenario.time_limit_s = 0.0
	scenario.clock_s = -1
	scenario.session_seed = 1
	var problems := "\n".join(scenario.problems())
	for expected: String in [
		"bots is",
		"map res://nowhere.tscn",
		"forced to role medic",
		"bot 99",
		"setting speed",
		"expected end aliens",
		"time_limit_s",
		"session_seed 1 is below",
		"clock_s -1 is outside 0 to 65535",
	]:
		assert_str(problems).contains(expected)
	scenario.scripts[0].steps.push_front(StepJoin.new())
	assert_str("\n".join(scenario.problems())).contains("bot 1 sends the setup's settings")
	scenario.expected_ends = []
	assert_str("\n".join(scenario.problems())).contains("no expected end")
	scenario.mode = null
	assert_array(Array(scenario.problems())).is_equal(["no mode"])


func test_a_scenario_without_a_map_plays_the_mode_s_test_bench() -> void:
	# #767: bots play only the flat levels (§9.7), so an unnamed map is the mode's first test bench,
	# which the host's bot asks for in the setup, since no match starts on a bench.
	var scenario := _scenario()
	assert_str(scenario.played_map()).is_equal(FixtureBaseMode.MAP)
	assert_dict(scenario.setup_change()).is_empty()
	scenario.mode.bench_maps = PackedStringArray([FixtureBaseMode.SMALL_MAP])
	assert_str(scenario.played_map()).is_equal(FixtureBaseMode.SMALL_MAP)
	assert_dict(scenario.setup_change()).is_equal(
		{"settings": {}, "map": FixtureBaseMode.SMALL_MAP}
	)
	assert_array(Array(scenario.problems())).is_empty()
	# A named map wins, and is sent even when it is the default (as before #767).
	scenario.map = FixtureBaseMode.MAP
	assert_str(scenario.played_map()).is_equal(FixtureBaseMode.MAP)
	assert_dict(scenario.setup_change()).is_equal({"settings": {}, "map": FixtureBaseMode.MAP})
	scenario.mode = null
	scenario.map = ""
	assert_str(scenario.played_map()).is_empty()
	assert_dict(scenario.setup_change()).is_empty()


func test_the_bots_talk_in_spurts_by_default_or_continuously() -> void:
	# M5-1: the bots' synthetic voice (ARCHITECTURE §4.6).
	var scenario := _scenario()
	assert_int(scenario.voice).is_equal(BotScenario.Voice.SPURTS)
	scenario.voice = BotScenario.Voice.CONTINUOUS
	assert_array(Array(scenario.problems())).is_empty()
	# A value no member has, as a hand-edited .tres can hold.
	scenario.set("voice", 2)
	assert_str("\n".join(scenario.problems())).contains("voice 2 is neither SPURTS nor CONTINUOUS")
	scenario.set("voice", -1)
	assert_str("\n".join(scenario.problems())).contains("voice -1 is neither SPURTS nor CONTINUOUS")


func test_steps_and_targets_report_their_problems() -> void:
	var scenario := _scenario()
	var walk := StepWalkTo.new()
	walk.stop_m = -1.0
	var pick := StepPickUp.new()
	pick.target = ScenarioTarget.new()
	pick.target.kind = ScenarioTarget.Kind.NEAREST
	var wait := StepWait.new()
	wait.expect_rejected = &"too_soon"
	var downed_pick := StepPickUp.new()
	downed_pick.target = ScenarioTarget.new()
	downed_pick.expect_rejected = &"not_accepted"
	scenario.scripts[0].steps.append_array([walk, pick, wait, downed_pick])
	var problems := scenario.problems()
	(
		assert_array(Array(problems))
		. is_equal(
			[
				"bot 1, WalkTo: no target",
				"bot 1, WalkTo: stop_m is negative",
				"bot 1, PickUp: nearest names no item kind",
				"bot 1, Wait: expect_rejected on a step that sends no intent",
			]
		)
	)


func test_a_join_is_the_first_step_or_follows_a_leave() -> void:
	# Before its Welcome a bot runs only a Join: a Join anywhere else would never run.
	var scenario := _scenario()
	scenario.settings = {}
	scenario.scripts[0].steps.append(StepJoin.new())
	assert_array(Array(scenario.problems())).is_equal(
		["bot 1: a Join is its first step or directly follows its own Leave"]
	)
	scenario.scripts[0].steps.push_front(StepJoin.new())
	assert_array(Array(scenario.problems())).is_equal(
		["bot 1: a Join is its first step or directly follows its own Leave"]
	)
	scenario.scripts[0].steps.pop_back()
	assert_array(Array(scenario.problems())).is_empty()


func test_a_join_may_follow_the_bots_own_leave() -> void:
	# P12 (a) of the returning-players ADR: a bot that left joins again, as its own Join step.
	var scenario := _scenario()
	scenario.scripts.append(BotScript.new())
	scenario.scripts[1].steps = [StepLeave.new(), _join(1.0, 5.0), StepReady.new()]
	assert_array(Array(scenario.problems())).is_empty()
	# Twice is fine too: the rule is per Leave.
	scenario.scripts[1].steps.append_array([StepLeave.new(), _join(6.0, 9.0)])
	assert_array(Array(scenario.problems())).is_empty()


func test_a_join_after_a_leave_has_its_deadline_and_nothing_between() -> void:
	var scenario := _scenario()
	scenario.scripts.append(BotScript.new())
	scenario.scripts[1].steps = [StepLeave.new(), StepReady.new(), _join(1.0, 5.0)]
	assert_array(Array(scenario.problems())).is_equal(
		["bot 2: a Join is its first step or directly follows its own Leave"]
	)
	# A Join as the second step, after a step that is no Leave, is misplaced as well.
	scenario.scripts[1].steps = [StepReady.new(), _join(1.0, 0.0)]
	assert_array(Array(scenario.problems())).is_equal(
		["bot 2: a Join is its first step or directly follows its own Leave"]
	)
	scenario.scripts[1].steps = [StepLeave.new(), _join(5.0, 5.0)]
	assert_array(Array(scenario.problems())).is_equal(
		["bot 2: a Join after its Leave needs deadline_s above at_s (5.0 s)"]
	)
	# A first Join has no deadline: its refusal fails it at once.
	scenario.scripts[1].steps = [_join(1.0, 5.0), StepLeave.new()]
	assert_array(Array(scenario.problems())).is_equal(
		["bot 2: a first Join has no deadline_s; only a Join after its Leave retries"]
	)
	# The host's own client sends the setup and hosts the session: it never leaves to return.
	scenario.settings = {}
	scenario.scripts[0].steps.append_array([StepLeave.new(), _join(1.0, 5.0)])
	scenario.scripts[1].steps = []
	assert_array(Array(scenario.problems())).is_equal(
		["bot 1 is the host's own client: it does not join again after its Leave"]
	)


func test_every_step_names_itself_as_in_section_9_7() -> void:
	var names: Array[StringName] = []
	for step: ScenarioStep in [
		StepJoin.new(),
		StepLoadAck.new(),
		StepReady.new(),
		StepSetting.new(),
		StepReturnToLobby.new(),
		StepWaitFor.new(),
		StepWait.new(),
		StepWalkTo.new(),
		StepPickUp.new(),
		StepPutDown.new(),
		StepUse.new(),
		StepJump.new(),
		StepExpect.new(),
		StepExpectNone.new(),
		StepLeave.new(),
		StepRaise.new(),
		StepStopRaise.new(),
		StepGiveUp.new(),
		StepSwap.new(),
		StepNextStage.new(),
		StepTalk.new(),
		StepThrow.new(),
		StepInteract.new(),
		StepDraw.new(),
		StepExpectDrunk.new()
	]:
		names.append(step.step_name())
	assert_array(names).is_equal(
		[
			&"Join",
			&"LoadAck",
			&"Ready",
			&"Setting",
			&"ReturnToLobby",
			&"WaitFor",
			&"Wait",
			&"WalkTo",
			&"PickUp",
			&"PutDown",
			&"Use",
			&"Jump",
			&"Expect",
			&"ExpectNone",
			&"Leave",
			&"Raise",
			&"StopRaise",
			&"GiveUp",
			&"Swap",
			&"NextStage",
			&"Talk",
			&"Throw",
			&"Interact",
			&"Draw",
			&"ExpectDrunk"
		]
	)
	# The steps that send an intent, so expect_rejected applies (Join sends Hello).
	assert_bool(StepJoin.new().sends_intent()).is_true()
	assert_bool(StepUse.new().sends_intent()).is_true()
	assert_bool(StepWalkTo.new().sends_intent()).is_false()
	assert_str(StepUse.new().until).is_equal("Swung")
	for raising: ScenarioStep in [
		StepRaise.new(),
		StepStopRaise.new(),
		StepGiveUp.new(),
		StepSwap.new(),
		StepNextStage.new(),
		StepThrow.new(),
		StepInteract.new(),
		StepDraw.new()
	]:
		assert_bool(raising.sends_intent()).is_true()


func test_a_raise_step_targets_a_bot() -> void:
	var raise := StepRaise.new()
	assert_array(Array(raise.problems())).is_equal(["no target"])
	raise.target = ScenarioTarget.new()
	assert_array(Array(raise.problems())).is_equal(["a Raise targets a player: bot(i)"])
	raise.target.kind = ScenarioTarget.Kind.BOT
	raise.target.bot = 3
	raise.hold_s = -1.0
	assert_array(Array(raise.problems())).is_equal(["hold_s -1.0 is outside 0 to 600"])
	raise.hold_s = 2.0
	assert_array(Array(raise.problems())).is_empty()


func test_an_interact_step_names_a_station_and_the_event_its_use_emits() -> void:
	var interact := StepInteract.new()
	assert_array(Array(interact.problems())).is_equal(
		["no station", "no until: name the event the use emits"]
	)
	interact.station = ScenarioTarget.new()
	interact.until = &"FixtureNote"
	assert_array(Array(interact.problems())).is_equal(
		["an Interact names a station: station(kind, i)"]
	)
	interact.station.kind = ScenarioTarget.Kind.STATION
	interact.station.station_kind = &"panel"
	assert_array(Array(interact.problems())).is_empty()
	# A step that expects a refusal waits for that Rejected, not for an event.
	interact.until = &""
	interact.expect_rejected = &"unavailable"
	assert_array(Array(interact.problems())).is_empty()


func test_an_interact_step_may_name_the_nearest_item_of_a_kind_instead() -> void:
	# #1209: Cooking's boxes are items a take names in place of a station.
	var interact := StepInteract.new()
	interact.until = &"ItemPickedUp"
	interact.item = ScenarioTarget.new()
	assert_array(Array(interact.problems())).is_equal(
		["an Interact's item is the nearest of a kind: nearest(item_kind)"]
	)
	interact.item.kind = ScenarioTarget.Kind.NEAREST
	assert_array(Array(interact.problems())).is_equal(["nearest names no item kind"])
	interact.item.item_kind = &"box_bun_white"
	assert_array(Array(interact.problems())).is_empty()
	interact.station = ScenarioTarget.new()
	interact.station.kind = ScenarioTarget.Kind.STATION
	interact.station.station_kind = &"grill"
	assert_array(Array(interact.problems())).is_equal(
		["an Interact names a station or an item, not both"]
	)


func test_a_throw_step_faces_a_target_at_a_pitch_from_minus_90_to_90() -> void:
	var throw := StepThrow.new()
	assert_array(Array(throw.problems())).is_equal(["no towards"])
	throw.towards = ScenarioTarget.new()
	throw.pitch_deg = 90.5
	assert_array(Array(throw.problems())).is_equal(["pitch_deg 90.5 is outside -90 to 90"])
	throw.pitch_deg = NAN
	assert_array(Array(throw.problems())).is_equal(["pitch_deg nan is outside -90 to 90"])
	for pitch: float in [-90.0, 0.0, 30.0, 90.0]:
		throw.pitch_deg = pitch
		assert_array(Array(throw.problems())).is_empty()


## #1390: ExpectDrunk names itself (0) or another bot of the scenario, and a range within 0 to 255.
func test_an_expect_drunk_names_a_bot_of_the_scenario_and_a_range() -> void:
	var drunk := StepExpectDrunk.new()
	assert_bool(drunk.sends_intent()).is_false()
	assert_array(Array(drunk.problems())).is_empty()
	drunk.bot = 1
	drunk.at_least = 90
	drunk.at_most = 100
	drunk.within_s = 2.0
	assert_array(Array(drunk.problems())).is_empty()
	var scenario := _scenario()
	scenario.scripts[0].steps.append(drunk)
	assert_array(Array(scenario.problems())).is_empty()
	drunk.bot = 2
	assert_array(Array(scenario.problems())).is_empty()
	drunk.bot = 3
	assert_array(Array(scenario.problems())).contains_exactly(
		["bot 1, ExpectDrunk: bot 3 is outside 0 to 2"]
	)
	drunk.bot = -1
	drunk.at_least = 101
	drunk.within_s = -1.0
	(
		assert_array(Array(drunk.problems()))
		. contains_exactly(
			[
				"bot -1 is below 0",
				"at_least 101 to at_most 100 is no range within 0 to 255",
				"within_s is negative",
			]
		)
	)
	drunk.at_least = 0
	drunk.at_most = 256
	assert_array(Array(drunk.problems())).contains(
		["at_least 0 to at_most 256 is no range within 0 to 255"]
	)


## #1235: a misspelled event or field key in a `never`, an Expect, an ExpectNone or a WaitFor never
## matches, so it is a problem when the runner hands in the events a bot receives.
func test_events_and_fields_are_checked_against_the_receivable_events() -> void:
	var events: Dictionary[StringName, PackedStringArray] = {
		&"Died": PackedStringArray(["peer", "position"]),
		&"PhaseChanged": PackedStringArray(["phase"]),
	}
	var scenario := _scenario()
	var expect := StepExpect.new()
	expect.event = &"Died"
	expect.fields = {"peer": 2}
	var none := StepExpectNone.new()
	none.event = &"PhaseChanged"
	none.fields = {"phase": &"round"}
	var wait := StepWaitFor.new()
	wait.event = &"Died"
	var never := NeverEvent.new()
	never.event = &"Died"
	never.fields = {"peer": 1}
	scenario.scripts[0].steps.append_array([expect, none, wait])
	scenario.never = [never]
	assert_array(Array(scenario.problems(events))).is_empty()
	never.event = &"Dieed"
	none.fields = {"phsae": &"round"}
	expect.fields = {"peer": 2, "cause": &"fall"}
	wait.event = &"PhaseChange"
	(
		assert_array(Array(scenario.problems(events)))
		. contains_exactly(
			[
				"bot 1, Expect: event Died has no field cause",
				"bot 1, ExpectNone: event PhaseChanged has no field phsae",
				"bot 1, WaitFor: event PhaseChange is none a bot receives",
				"never 0: event Dieed is none a bot receives",
			]
		)
	)
	# Without the catalogue (a core-only caller) only the data's own shape is checked.
	assert_array(Array(scenario.problems())).is_empty()
	never.event = &""
	scenario.never.append(null)
	assert_array(Array(scenario.problems())).contains_exactly(
		["never 0 has no event", "never 1 is empty"]
	)


func _scenario() -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = FixtureBaseMode.mode()
	var crew := GameRole.new()
	crew.id = &"crew"
	scenario.mode.roles = [crew]
	scenario.bots = 2
	scenario.forced_roles = {2: &"crew"}
	scenario.expected_ends = [BotScenario.NONE]
	var script := BotScript.new()
	var ready := StepReady.new()
	var walk := StepWalkTo.new()
	walk.target = ScenarioTarget.new()
	walk.target.point = Vector3(1, 0, 1)
	script.steps = [ready, walk]
	scenario.scripts = [script]
	return scenario


func _join(at_s: float, deadline_s: float) -> StepJoin:
	var join := StepJoin.new()
	join.at_s = at_s
	join.deadline_s = deadline_s
	return join
