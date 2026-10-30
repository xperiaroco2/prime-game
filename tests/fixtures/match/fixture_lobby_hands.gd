class_name FixtureLobbyHands
extends RefCounted
## FixtureBaseMode with the hand and the belt in its lobby and countdown, as the base mode has them
## (#1388; a part's unit test never loads `content/`, ARCHITECTURE §9.6): FixtureItemModes' item
## kinds (`package` two-handed, `tool` one-handed with a Use that notes "tool used") and its
## PickUp, PutDown, Swap and Draw; the mode's Use with an empty hand starts a FixtureChannel of
## 1 s; an Interact on a placed station notes "interacted". Lobby and Countdown accept Interact,
## PickUp, PutDown, Swap, Draw and Use from the living and run ChannelTicks. No UseSecondary (no
## rule here takes it, so ModeCheck would refuse the mode; FixtureBar adds it with its mug, #1438),
## no Throw, no Pose.
## The `countdown_done` row runs no action (clearing(): ClearItems).

const P1 := 1
const P2 := 2
const P3 := 3
const HERE := Vector3.ZERO
## The intents the hall's things need (#1388), each from the living.
const HAND_INTENTS: Array[StringName] = [
	Intents.INTERACT,
	Intents.PICK_UP,
	Intents.PUT_DOWN,
	Intents.SWAP,
	Intents.DRAW,
	Intents.USE,
]


static func mode() -> GameMode:
	var made := FixtureBaseMode.mode()
	var items := FixtureItemModes.basic()
	made.player_rules.eye_height_m = FixtureItemModes.EYE_HEIGHT_M
	made.item_kinds = items.item_kinds
	made.actions = [
		FixtureItemModes.pick_up_rule(FixtureItemModes.REACH_M),
		FixtureItemModes.put_down_rule(FixtureItemModes.DISTANCE_M),
		FixtureItemModes.swap_rule(),
		FixtureItemModes.draw_rule(),
		FixtureModes.rule(Intents.USE, [ChannelFree.new()], [FixtureChannel.of(1.0)]),
		FixtureModes.rule(Intents.INTERACT, [], [FixtureNote.of("interacted")]),
	]
	for phase_id: StringName in [&"lobby", &"countdown"]:
		var spec := made.find_phase(phase_id)
		for intent: StringName in HAND_INTENTS:
			spec.accepts.append(AcceptSpec.of(intent, AcceptSpec.From.LIVING))
		spec.tick_systems.append(ChannelTicks.new())
	return made


## A started match of `made` (the lobby) that keeps its history, with `peers` joined, each standing
## at HERE plus 1 m per peer along x.
static func in_lobby(made: GameMode, peers: Array[int]) -> Match:
	var game := Match.new(made, 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	for peer: int in peers:
		FixtureItemModes.stand(game, peer, HERE + Vector3(peer, 0, 0))
	return game


## `peers` in the lobby, all ready: the countdown.
static func in_countdown(made: GameMode, peers: Array[int]) -> Match:
	var game := in_lobby(made, peers)
	for peer: int in peers:
		FixtureBaseMode.ready(game, peer)
	return game


## An item of `kind_id` laid at `peer`'s feet and picked up by it: in its hand.
static func give(game: Match, peer: int, kind_id: StringName) -> ItemState:
	var at := game.state.player(peer).position + Vector3(0, 0, -0.5)
	var item := FixtureItemModes.lay(game, kind_id, at)
	FixtureItemModes.pick_up(game, peer, item)
	return item


## `made` with ClearItems as the `countdown_done` row's action, as the base mode has it.
static func clearing(made: GameMode) -> GameMode:
	for row: Transition in made.transitions:
		if row.from == &"countdown" and row.outcome == CountdownPhase.COUNTDOWN_DONE:
			row.actions.append(ClearItems.new())
	return made


## The countdown's ticks through its end tick (entry + 100): loading.
static func through_countdown(game: Match) -> void:
	FixtureModes.run_ticks(game, 101)
