extends Node
## A preview of one screen of the game for `tools\run.cmd shot` (the M4 ADR's §6): the game's Ui
## fed by a fake ClientModel folded from events written here, as a host would send them. Dev only:
## nothing here reaches the game.

enum Preview { MENU, CONNECTING, LOBBY, LOADING, END, ESC, ROUND, TASKS }

const MODE := "res://content/modes/base_mode.tres"
const MAP := "res://levels/greybox/greybox.tscn"
## The round's fake facts (M4-8): the match clock's end, the package, the knife and its circle.
const ROUND_END_TICK := 100 + 20 * 271
const PACKAGE := 7
const KNIFE := 3
const CIRCLE := 2
const CIRCLE_COLOUR := Color(0.95, 0.75, 0.2)

@export var preview := Preview.MENU
## The preview shows the host's view (its settings, Back to lobby, Esc's confirmation).
@export var hosting := true
## The Esc menu's tab (Preview.ESC; #169): the Lobby tab, Resume, or the host's Leave or Quit.
@export var esc_tab := EscMenuState.Tab.LOBBY
## The Esc menu over the round instead of the lobby (no Lobby tab there).
@export var esc_in_round := false


func _ready() -> void:
	var mode := load(MODE) as GameMode
	var ui := GameUi.new()
	add_child(ui)
	ui.esc.lobby.set_mode(mode)
	var model := fake_model(mode, hosting)
	ui.reads_device_input = false
	match preview:
		Preview.MENU:
			ui.menu.set_reason(
				"The last session ended: %s." % EndReasons.words(DisconnectingEvent.LOAD_DEADLINE)
			)
			ui.show_screen(GameFlow.Screen.MENU)
		Preview.CONNECTING:
			ui.connecting.set_address("192.168.0.195:24600")
			ui.show_screen(GameFlow.Screen.CONNECTING)
		Preview.LOBBY:
			model.fold(&"PhaseChanged", {"phase": &"countdown", "end_tick": 160})
			ui.show_screen(GameFlow.Screen.LOBBY)
		Preview.LOADING:
			model.fold(&"PhaseChanged", {"phase": &"loading", "end_tick": -1})
			model.fold(&"LoadMatch", {"match_id": 0, "map": MAP, "settings": model.settings})
			model.fold(&"PlayerLoaded", {"peer": 1})
			model.fold(&"PlayerLoaded", {"peer": 2})
			ui.show_screen(GameFlow.Screen.LOADING)
		Preview.END:
			model.fold(&"PhaseChanged", {"phase": &"end", "end_tick": -1})
			model.fold(&"MatchEnded", {"side": &"dissidents"})
			ui.show_screen(GameFlow.Screen.END)
		Preview.ESC:
			if esc_in_round:
				fold_round(model, false)
			ui.show_screen(GameFlow.Screen.ROUND if esc_in_round else GameFlow.Screen.LOBBY)
			ui.open_esc(hosting, model)
			if esc_tab != EscMenuState.Tab.RESUME:
				# Pressing Resume would close the menu: in the round it is the tab Esc opens on.
				ui.esc.press(esc_tab)
		Preview.ROUND, Preview.TASKS:
			fold_round(model, true)
			ui.show_screen(GameFlow.Screen.ROUND)
			ui.show_tasks(preview == Preview.TASKS)
			var local := HudText.Local.new()
			local.stamina = 62.0
			local.hint = "E: pick up Knife"
			ui.refresh_round(model, mode, 100, local)
	ui.refresh(model, mode, 100, hosting)


## A lobby of three, the own player peer 1 (the host) or peer 2, with one shortfall.
static func fake_model(mode: GameMode, as_host: bool) -> ClientModel:
	var model := ClientModel.new(mode)
	var own := 1 if as_host else 2
	var welcome := WelcomeEvent.new(own, Vector3.ZERO, 1)
	(
		welcome
		. roster
		. assign(
			[
				{"peer": 1, "name": "Player1", "ready": true},
				{"peer": 2, "name": "Player2", "ready": true},
				{"peer": 3, "name": "Player3", "ready": false},
			]
		)
	)
	welcome.settings = mode.default_settings()
	welcome.map = MAP
	welcome.phase = &"lobby"
	model.fold(&"Welcome", welcome.to_dict())
	(
		model
		. fold(
			&"SettingsChanged",
			{
				"settings": mode.default_settings(),
				"id_sets": mode.default_id_sets(),
				"map": MAP,
				"shortfalls": PackedStringArray(["3 player(s), the mode plays with 4 to 10"]),
			}
		)
	)
	return model


## The round on top of fake_model (M4-8): the own player (peer 1) a dissident with peer 3, a
## package in its hands and the knife on its belt, two Delivery tasks, half of the progress done;
## `with_items` false leaves the items and circles out.
static func fold_round(model: ClientModel, with_items := true) -> void:
	model.fold(&"PhaseChanged", {"phase": &"round", "end_tick": ROUND_END_TICK})
	model.fold(&"RoleAssigned", {"role": &"dissident"})
	model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([1, 3])})
	model.fold(&"SelfStatus", {"health": 75000, "stamina": 62000, "sprint_available": true})
	model.fold(&"TaskState", {"task": 0, "type": &"delivery", "done": 1, "total": 3})
	model.fold(&"TaskState", {"task": 1, "type": &"delivery", "done": 2, "total": 2})
	model.fold(&"TaskProgress", {"done": 3, "total": 5})
	if not with_items:
		return
	model.fold(
		&"StationPlaced",
		{
			"station": CIRCLE,
			"kind": &"circle",
			"colour": CIRCLE_COLOUR,
			"position": Vector3(6, 0, -8)
		}
	)
	(
		model
		. fold(
			&"ItemSpawned",
			{
				"item": PACKAGE,
				"kind": &"package",
				"position": Vector3(0, 0, -2),
				"station": CIRCLE,
				"colour": CIRCLE_COLOUR,
			}
		)
	)
	model.fold(&"ItemSpawned", {"item": KNIFE, "kind": &"knife", "position": Vector3(1, 0, -1)})
	model.fold(&"ItemPickedUp", {"peer": model.own_peer, "item": KNIFE})
	model.fold(&"ItemPickedUp", {"peer": model.own_peer, "item": PACKAGE, "belted": KNIFE})
