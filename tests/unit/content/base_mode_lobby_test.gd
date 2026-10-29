extends GdUnitTestSuite
## The base mode's Lobby and Countdown in `content/` (#1388, provisional data): both take Interact,
## PickUp, PutDown, Swap, Draw and Use from the living, never Throw, Raise, StopRaise, GiveUp or
## Pose; both run LifeTicks (its Respawn on the hall's `lobby_player` markers), ChannelTicks and
## VanishTicks, which ModeCheck demands of those intents mode-wide; the `countdown_done` row runs
## ClearItems, so a package picked up in the hall is gone in Loading and never reaches the round.
## Loads `content/` and the levels on purpose (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"
const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")
const GREYBOX := "res://levels/greybox/greybox.tscn"
const P1 := 1
const P2 := 2
const HALL: Array[StringName] = [&"lobby", &"countdown"]
const TAKEN: Array[StringName] = [
	Intents.INTERACT, Intents.PICK_UP, Intents.PUT_DOWN, Intents.SWAP, Intents.DRAW, Intents.USE
]
const REFUSED: Array[StringName] = [
	Intents.THROW, Intents.RAISE, Intents.STOP_RAISE, Intents.GIVE_UP, Intents.POSE
]


func test_the_hall_takes_the_hand_the_belt_and_interact_from_the_living() -> void:
	var mode := load(BASE_MODE) as GameMode
	for phase_id: StringName in HALL:
		var spec := mode.find_phase(phase_id)
		for intent: StringName in TAKEN:
			(
				assert_int(spec.senders_of(intent))
				. override_failure_message("%s %s" % [phase_id, intent])
				. is_equal(AcceptSpec.From.LIVING)
			)
		for intent: StringName in REFUSED:
			(
				assert_int(spec.senders_of(intent))
				. override_failure_message("%s %s" % [phase_id, intent])
				. is_equal(0)
			)


func test_the_hall_runs_life_channel_and_vanish_ticks() -> void:
	var mode := load(BASE_MODE) as GameMode
	for phase_id: StringName in HALL:
		var systems := mode.find_phase(phase_id).tick_systems
		assert_int(systems.size()).is_equal(3)
		assert_object(systems[0]).is_instanceof(LifeTicks)
		assert_object(systems[1]).is_instanceof(ChannelTicks)
		assert_object(systems[2]).is_instanceof(VanishTicks)
		var respawn := (systems[0] as LifeTicks).respawn
		assert_object(respawn).is_not_null()
		assert_str(String(respawn.tag)).is_equal("lobby_player")


func test_mode_check_needs_the_hall_s_life_ticks() -> void:
	# The control: without them, Use's Strike and Interact's car repair are refused in the hall.
	var mode := (load(BASE_MODE) as GameMode).duplicate(true) as GameMode
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
	mode.find_phase(&"lobby").tick_systems = mode.find_phase(&"lobby").tick_systems.slice(1)
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("phase lobby")
	assert_str(errors).contains("LifeTicks")


func test_countdown_done_clears_the_items_and_a_cancel_does_not() -> void:
	var mode := load(BASE_MODE) as GameMode
	for row: Transition in mode.transitions:
		if row.from != &"countdown":
			continue
		if row.outcome == CountdownPhase.COUNTDOWN_DONE:
			assert_int(row.actions.size()).is_equal(1)
			assert_object(row.actions[0]).is_instanceof(ClearItems)
		else:
			assert_array(row.actions).is_empty()


func test_a_package_held_in_the_hall_never_reaches_the_round() -> void:
	var mode := load(BASE_MODE) as GameMode
	var game := Match.new(mode, 7, FlatWorldQuery.new(), _layouts_for(mode))
	game.state.map = GREYBOX
	game.keep_history = true
	assert_bool(game.start(0)).is_true()
	for peer: int in [P1, P2]:
		FixtureBaseMode.join(game, peer)
	var player := game.state.player(P1)
	var at := player.position + Vector3(0, 0, -0.5)
	var package := game.state.add_item(mode.find_item_kind(&"package"), at)
	FixtureModes.send(game, Intents.PICK_UP, P1, {"item": package.id})
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(player.held_item).is_equal(package.id)
	assert_int(package.kind.hands).is_equal(2)
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	assert_str(game.phase_id()).is_equal("countdown")
	for i in 200:
		if game.phase_id() != &"countdown":
			break
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("loading")
	assert_bool(game.state.items.is_empty()).is_true()
	assert_int(player.held_item).is_equal(-1)
	var vanished := game.view_of(P2).events_named(&"ItemVanished")
	assert_int(vanished.size()).is_equal(1)
	assert_int((vanished[0] as ItemVanishedEvent).item).is_equal(package.id)
	for peer: int in [P1, P2]:
		FixtureBaseMode.load_ack(game, peer)
	for i in 200:
		if game.phase_id() == &"round":
			break
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.items.values().has(package)).is_false()
	for peer: int in [P1, P2]:
		assert_int(game.state.player(peer).held_item).is_equal(-1)
	assert_array(Array(game.diagnostics)).is_empty()


func _layouts_for(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var levels := MarkerReader.read_levels(
		mode, FlatWorldQuery.new(), ScenarioLevels.unsnapped(mode)
	)
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts
