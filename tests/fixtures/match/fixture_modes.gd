class_name FixtureModes
extends RefCounted
## Game modes, layouts and drivers for the unit tests of the match loop, built in code (a part's
## unit tests never load `content/`, ARCHITECTURE §9.6).
##
## basic(): lobby (FixturePhase: Hello, SetReady, `all_ready`) -> round (RoundPhase: Use from the
## living, MoveClaim from the living and the downed; LifeTicks; win checks; the clock) -> end
## (FixturePhase: ReturnToLobby from the host, `back`) -> lobby. The deal places players on
## `round_player`; `End -> Lobby` on `lobby_player`. Win conditions, in order: crew when peer 0's
## counter `crew_win` >= 1, dissidents when `dissidents_win` >= 1. The `won` row emits a note
## "won <side>".

const LOBBY := "fixture://lobby"
const MAP := "fixture://map"
const LIVING := AcceptSpec.From.LIVING
const DOWNED := AcceptSpec.From.DOWNED


static func basic() -> GameMode:
	var mode := GameMode.new()
	mode.min_players = 1
	mode.max_players = 4
	mode.player_rules = player_rules()
	mode.settings = [setting(&"knives", 2, 0, 10)]
	mode.sides = [side(&"crew"), side(&"dissidents")]
	mode.roles = [role(&"crew", &"crew", false), role(&"dissident", &"dissidents", true)]
	mode.lobby_level = LOBBY
	mode.maps = PackedStringArray([MAP])
	mode.actions = [rule(Intents.USE, [], [FixtureNote.of("used")])]
	mode.task_types = [FixtureTaskType.new()]
	mode.win_conditions = [
		win(&"crew", FixtureCounterAtLeast.of(&"crew_win")),
		win(&"dissidents", FixtureCounterAtLeast.of(&"dissidents_win")),
	]
	var lobby := phase(
		&"lobby",
		FixturePhase,
		{&"reports_all_ready": 1.0},
		[
			AcceptSpec.of(Intents.HELLO, AcceptSpec.From.NEWCOMER),
			AcceptSpec.of(Intents.SET_READY, AcceptSpec.From.PLAYER),
			AcceptSpec.of(Intents.MOVE_CLAIM, LIVING),
		]
	)
	lobby.level = PhaseSpec.Level.LOBBY
	lobby.snapshots = true
	lobby.voice_rule = FixtureVoice.new()
	var round_spec := phase(
		&"round",
		RoundPhase,
		{},
		[AcceptSpec.of(Intents.USE, LIVING), AcceptSpec.of(Intents.MOVE_CLAIM, LIVING | DOWNED)]
	)
	round_spec.level = PhaseSpec.Level.MAP
	round_spec.tick_systems = [LifeTicks.new()]
	round_spec.checks_wins = true
	round_spec.clock_runs = true
	round_spec.snapshots = true
	round_spec.voice_rule = FixtureVoice.new()
	var end := phase(
		&"end",
		FixturePhase,
		{&"reports_back": 1.0},
		[AcceptSpec.of(Intents.RETURN_TO_LOBBY, AcceptSpec.From.HOST)]
	)
	end.level = PhaseSpec.Level.MAP
	mode.phases = [lobby, round_spec, end]
	mode.first_phase = &"lobby"
	var won_note := FixtureNote.of("won")
	won_note.with_argument = true
	mode.transitions = [
		row(&"lobby", &"all_ready", &"round", [place(&"round_player")]),
		row(&"round", Match.WON, &"end", [won_note]),
		row(&"end", &"back", &"lobby", [place(&"lobby_player")]),
	]
	return mode


## The MVP's numbers of ARCHITECTURE §9.5, written out: PlayerRules' class defaults are 0.
static func player_rules() -> PlayerRules:
	var rules := PlayerRules.new()
	rules.health = 100
	rules.stamina = 100
	rules.stamina_regen_per_s = 15
	rules.walk_speed_mps = 4.5
	rules.sprint_speed_mps = 7.0
	rules.sprint_cost_per_s = 20
	rules.sprint_start = 20
	rules.jump_height_m = 1.0
	rules.jump_cost = 10
	rules.crawl_speed_mps = 1.0
	rules.knockdown_s = 10.0
	rules.capsule_radius_m = 0.4
	rules.capsule_height_m = 1.8
	rules.eye_height_m = 1.6
	rules.step_height_m = 0.3
	return rules


## A lobby with `count` lobby_player markers and a map with `count` round_player markers.
static func layouts(count: int = 4) -> Dictionary[String, LevelLayout]:
	var lobby := LevelLayout.new(LOBBY)
	var map := LevelLayout.new(MAP)
	for i in count:
		lobby.add_marker(&"lobby_player", Vector3(i, 0, 0))
		map.add_marker(&"round_player", Vector3(10 + i, 0, 5))
	return {LOBBY: lobby, MAP: map}


## A match of `mode` that keeps its history for view_of().
static func create(mode: GameMode, seed_value: int = 7) -> Match:
	var game := Match.new(mode, seed_value, FlatWorldQuery.new(), layouts())
	game.keep_history = true
	return game


## A started match of `mode` whose players `peers` joined in the lobby.
static func started(mode: GameMode, peers: Array[int], seed_value: int = 7) -> Match:
	var game := create(mode, seed_value)
	game.start(0)
	for peer: int in peers:
		send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	return game


## `peers` joined and all ready: the match is in the round.
static func in_round(mode: GameMode, peers: Array[int], seed_value: int = 7) -> Match:
	var game := started(mode, peers, seed_value)
	for peer: int in peers:
		send(game, Intents.SET_READY, peer, {"ready": true})
	return game


## Applies a command stamped with the next tick.
static func send(
	game: Match, kind: StringName, peer: int, args: Dictionary = {}, seq: int = 0
) -> void:
	game.apply(MatchCommand.new(kind, peer, game.ticked_through() + 1, args, seq))


## Runs the next `count` ticks.
static func run_ticks(game: Match, count: int) -> void:
	for i in count:
		game.tick(game.ticked_through() + 1)


## The texts of every FixtureNoteEvent emitted so far, in order.
static func notes(game: Match) -> Array[String]:
	var found: Array[String] = []
	for emitted: EmittedEvent in game.emitted():
		if emitted.event is FixtureNoteEvent:
			found.append((emitted.event as FixtureNoteEvent).text)
	return found


## The names of the emitted events, in order.
static func names(game: Match) -> Array[StringName]:
	var found: Array[StringName] = []
	for emitted: EmittedEvent in game.emitted():
		found.append(emitted.event.event_name())
	return found


## Every emitted event with its tick and recipients, as plain data.
static func describe(game: Match) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for emitted: EmittedEvent in game.emitted():
		found.append(emitted.describe())
	return found


## The Rejected reasons `peer` received, in order.
static func rejections(game: Match, peer: int) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"Rejected"):
		found.append((event as RejectedEvent).reason)
	return found


static func setting(id: StringName, value: int, low: int, high: int) -> SettingSpec:
	var spec := SettingSpec.new()
	spec.id = id
	spec.default_value = value
	spec.min_value = low
	spec.max_value = high
	return spec


static func side(id: StringName) -> SideSpec:
	var spec := SideSpec.new()
	spec.id = id
	spec.display_name = String(id).capitalize()
	return spec


static func role(id: StringName, side_id: StringName, knows_teammates: bool) -> GameRole:
	var made := GameRole.new()
	made.id = id
	made.side = side_id
	made.knows_teammates = knows_teammates
	return made


static func rule(
	trigger: StringName, conditions: Array[Condition], effects: Array[RuleEffect]
) -> Rule:
	var made := Rule.new()
	made.trigger = trigger
	made.conditions = conditions
	made.effects = effects
	return made


static func win(side_id: StringName, condition: Condition) -> WinCondition:
	var made := WinCondition.new()
	made.id = side_id
	made.side = side_id
	made.conditions = [condition]
	return made


static func phase(
	id: StringName,
	phase_class: Script,
	settings: Dictionary[StringName, float],
	accepts: Array[AcceptSpec]
) -> PhaseSpec:
	var spec := PhaseSpec.new()
	spec.id = id
	spec.phase_class = phase_class
	spec.settings = settings
	spec.accepts = accepts
	return spec


static func row(
	from: StringName, outcome: StringName, to: StringName, actions: Array[RuleEffect]
) -> Transition:
	var made := Transition.new()
	made.from = from
	made.outcome = outcome
	made.to = to
	made.actions = actions
	return made


static func place(tag: StringName) -> PlacePlayers:
	var effect := PlacePlayers.new()
	effect.tag = tag
	return effect
