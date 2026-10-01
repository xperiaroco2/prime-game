extends Node
## A preview of one screen of the game for `tools\run.cmd shot` (the M4 ADR's §6): the game's Ui
## fed by a fake ClientModel folded from events written here, as a host would send them. Dev only:
## nothing here reaches the game.

enum Preview { MENU, CONNECTING, LOBBY, LOADING, END, ESC }

const MODE := "res://content/modes/base_mode.tres"
const MAP := "res://levels/greybox/greybox.tscn"

@export var preview := Preview.MENU
## The preview shows the host's view (its settings, Back to lobby, Esc's confirmation).
@export var hosting := true


func _ready() -> void:
	var mode := load(MODE) as GameMode
	var ui := GameUi.new()
	add_child(ui)
	ui.lobby.set_mode(mode)
	var model := fake_model(mode, hosting)
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
			ui.show_screen(GameFlow.Screen.LOBBY)
			ui.open_esc(hosting)
			ui.esc.ask_quit()
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
