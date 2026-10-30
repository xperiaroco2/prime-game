class_name FixtureBar
extends RefCounted
## FixtureLobbyHands with a bar as the base mode has one (#1390; a part's unit test never loads
## `content/`, ARCHITECTURE §9.6): item kinds `mug` (one-handed, at most MUGS, vanishing after
## MUG_S, its Use a Drink of AMOUNT into `mug_empty`) and `mug_empty` (one-handed, at most EMPTIES,
## vanishing after EMPTY_S, no Use); the station kind `tap` (spawn tag `tap`), whose Interact at the
## tap and in sight gives a mug (GiveItem); PlayerRules' drunk scale MAX, TOO_MUCH, POINT_S. Lobby
## and Countdown run StationTicks (the tap), DrunkTicks and VanishTicks; `countdown_done` runs
## ClearItems and ClearStations. The mode has no Use rule of its own (the base mode has none).
## A reaction on `drunk_too_much` notes "too much <peer>" (the fact's player). The lobby layout
## holds one `tap` marker at TAP. guarded() adds the base mode's pour Cooldown.

const P1 := FixtureLobbyHands.P1
const P2 := FixtureLobbyHands.P2
const P3 := FixtureLobbyHands.P3
const TAP := Vector3(6, 0, -2)
const MUGS := 9
const EMPTIES := 2
const MUG_S := 10
const EMPTY_S := 5
const AMOUNT := 40
const MAX := 100
const TOO_MUCH := 90
const POINT_S := 1.0
const POUR_KEY := &"tap_pour"
const POUR_S := 0.25


static func mode() -> GameMode:
	var made := FixtureLobbyHands.clearing(FixtureLobbyHands.mode())
	# As in the base mode, no rule of the mode takes a Use: an empty mug's Use finds none.
	var kept: Array[Rule] = []
	for rule: Rule in made.actions:
		if rule.trigger != Intents.USE:
			kept.append(rule)
	made.actions = kept
	var empty := FixtureItemModes.item_kind(&"mug_empty", [])
	empty.max_items = EMPTIES
	empty.vanish_seconds = EMPTY_S
	var effect := Drink.new()
	effect.empty_kind = empty
	effect.amount = AMOUNT
	var mug := FixtureItemModes.item_kind(
		&"mug", [FixtureModes.rule(Intents.USE, [], [effect] as Array[RuleEffect])]
	)
	mug.max_items = MUGS
	mug.vanish_seconds = MUG_S
	made.item_kinds.append(mug)
	made.item_kinds.append(empty)
	var give := GiveItem.new()
	give.kind = mug
	var placing := StationTicks.new()
	placing.kind = tap_kind(give)
	made.player_rules.drunk_max = MAX
	made.player_rules.drunk_too_much_at = TOO_MUCH
	made.player_rules.drunk_point_s = POINT_S
	var too_much := FixtureNote.of("too much")
	too_much.with_fact_player = true
	made.reactions.append(
		FixtureModes.rule(Facts.DRUNK_TOO_MUCH, [], [too_much] as Array[RuleEffect])
	)
	for phase_id: StringName in [&"lobby", &"countdown"]:
		var spec := made.find_phase(phase_id)
		spec.tick_systems.append(placing)
		spec.tick_systems.append(DrunkTicks.new())
		spec.tick_systems.append(VanishTicks.new())
	for row: Transition in made.transitions:
		if row.from == &"countdown" and row.outcome == CountdownPhase.COUNTDOWN_DONE:
			row.actions.append(ClearStations.new())
	return made


## mode() with the base mode's flood guard on the pour: a Cooldown of POUR_S on the key POUR_KEY
## after the tap's conditions (the other tests pour on one tick, so mode() leaves it out).
static func guarded() -> GameMode:
	var made := mode()
	var cooldown := Cooldown.new()
	cooldown.key = POUR_KEY
	cooldown.seconds = POUR_S
	for kind: StationKind in Stations.kinds_in(made):
		if kind.id == &"tap":
			kind.actions[0].conditions.append(cooldown)
	return made


## The station kind `tap`: radius 1.5 m, height 2 m, its Interact at it and in sight runs `give`.
static func tap_kind(give: RuleEffect) -> StationKind:
	var kind := StationKind.new()
	kind.id = &"tap"
	kind.spawn_tag = &"tap"
	kind.radius_m = 1.5
	kind.height_m = 2.0
	kind.actions = [
		FixtureModes.rule(
			Intents.INTERACT,
			[AtStation.new(), StationInSight.new()] as Array[Condition],
			[give] as Array[RuleEffect]
		)
	]
	return kind


## FixtureBaseMode's layouts with the `tap` marker at TAP in the lobby.
static func layouts() -> Dictionary[String, LevelLayout]:
	var made := FixtureBaseMode.layouts()
	made[FixtureBaseMode.LOBBY].add_marker(&"tap", TAP)
	return made


## A started match of `made` that keeps its history, `peers` joined and standing at the tap, after
## one tick (the tap stands).
static func at_bar(made: GameMode, peers: Array[int]) -> Match:
	var game := Match.new(made, 7, FlatWorldQuery.new(), layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	FixtureModes.run_ticks(game, 1)
	for peer: int in peers:
		FixtureItemModes.stand(game, peer, TAP + Vector3(0.3 * peer, 0, 0.5))
	return game


## The id of the tap's station, or -1.
static func tap_id(game: Match) -> int:
	for id: int in game.state.stations:
		if game.state.stations[id].kind.id == &"tap":
			return id
	return -1


## `peer` pours (Interact at the tap) with `seq`.
static func pour(game: Match, peer: int, seq := 0) -> void:
	FixtureModes.send(game, Intents.INTERACT, peer, {"station": tap_id(game)}, seq)


## `peer` drinks what it holds (Use) with `seq`.
static func drink(game: Match, peer: int, seq := 0) -> void:
	FixtureModes.send(game, Intents.USE, peer, {"facing": Vector3.FORWARD}, seq)
