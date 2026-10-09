extends Node
## A preview of one screen of the game for `tools\run.cmd shot` (the M4 ADR's §6): the game's Ui
## fed by a fake ClientModel folded from events written here, as a host would send them. Dev only:
## nothing here reaches the game.

## New previews go last: the preview scenes save the numbers.
enum Preview { MENU, CONNECTING, LOBBY, LOADING, END, ESC, ROUND, TASKS, PREGAME, MENU_VOICE }

const MODE := "res://content/modes/base_mode.tres"
const MAP := "res://levels/greybox/greybox.tscn"
## A code as the lobby and the connecting screen show one (SignalCodec's alphabet).
const PREVIEW_CODE := "K7M2QX"
## The version lines of fail-version (JoinProgress.version_text), made up for the preview.
const PREVIEW_HOST_VERSION := "13 (a1b2c3)"
const PREVIEW_OWN_VERSION := "12 (9f8e7d)"
## The round's fake facts (M4-8): the match clock's end, the package, the knife and its circle.
const ROUND_END_TICK := 100 + 20 * 271
const PACKAGE := 7
const KNIFE := 3
const CIRCLE := 2
const CIRCLE_COLOUR := Color(0.95, 0.75, 0.2)

@export var preview := Preview.MENU
## The preview shows the host's view (its settings, Esc's confirmation).
@export var hosting := true
## The Esc menu's tab (Preview.ESC; #169): the Lobby tab, Resume, Voice, Controls (#211), or the
## host's Leave or Quit.
@export var esc_tab := EscMenuState.Tab.LOBBY
## The Esc menu over the round instead of the lobby (no Lobby tab there).
@export var esc_in_round := false
## The Voice tab (M5-6), or the main menu's Voice page (#301), as without the voice addon.
@export var voice_unavailable := false
## The Controls tab (#211) with Map and tasks on V, Talk's key: both rows marked "Same key". The
## preview's controls stay in memory and the InputMap untouched.
@export var controls_clash := false
## The language of the words (Languages.ENGLISH or UKRAINIAN) and the large-text theme (#289).
@export var language := Languages.ENGLISH
@export var large_text := false
## The post game (Preview.END, #498), from an Engineer's view as the handoff draws it: the side
## that won (`crew`: the own team, the plate; `dissidents`: plain text), the host's reason id
## and the round's seconds (the handoff's sample 7:41).
@export var end_winner: StringName = &"crew"
@export var end_reason: StringName = &"all_tasks"
@export var end_round_seconds := 461
## The connecting screen's state (Preview.CONNECTING; #494): finding, connecting-direct, joined,
## a failure's (ConnectingScreen.FAILURES), or load (Preview.LOADING shows load).
@export var s3_state: StringName = &"finding"


func _ready() -> void:
	var mode := load(MODE) as GameMode
	# English on every machine unless `language` says otherwise, as a Game with no command line
	# (Languages.apply): the words built in code (the Controls tab's, #211) follow the language,
	# so a shot would follow the PC's.
	TranslationServer.set_locale(language)
	var ui := GameUi.new()
	add_child(ui)
	ui.set_large_text(large_text)
	ui.esc.lobby.set_mode(mode)
	var model := fake_model(mode, hosting)
	ui.reads_device_input = false
	var code_line := JoinProgress.code_text(PREVIEW_CODE, false)
	ui.lobby_hud.show_code(code_line)
	ui.esc.lobby.show_code(code_line, PREVIEW_CODE)
	match preview:
		Preview.MENU:
			ui.menu.set_reason(
				"The last session ended: %s." % EndReasons.words(DisconnectingEvent.LOAD_DEADLINE)
			)
			ui.show_screen(GameFlow.Screen.MENU)
		Preview.MENU_VOICE:
			ui.show_screen(GameFlow.Screen.MENU)
			ui.menu.open_voice()
			ui.menu.voice.show_facts(fake_voice(not voice_unavailable))
		Preview.CONNECTING:
			ui.show_screen(show_s3_state(ui.connecting, s3_state))
		Preview.LOBBY:
			model.fold(&"PhaseChanged", {"phase": &"countdown", "end_tick": 160})
			ui.show_screen(GameFlow.Screen.LOBBY)
		Preview.LOADING:
			model.fold(&"PhaseChanged", {"phase": &"loading", "end_tick": -1})
			model.fold(&"LoadMatch", {"match_id": 0, "map": MAP, "settings": model.settings})
			model.fold(&"PlayerLoaded", {"peer": 1})
			ui.show_screen(GameFlow.Screen.LOADING)
			ui.connecting.set_load_fraction(0.62)
		Preview.PREGAME:
			model.fold(&"LoadMatch", {"match_id": 0, "map": MAP, "settings": model.settings})
			model.fold(&"RoleAssigned", {"role": &"dissident"})
			model.fold(&"PhaseChanged", {"phase": &"pregame", "end_tick": 160})
			ui.show_screen(GameFlow.Screen.PREGAME)
		Preview.END:
			model.fold(&"RoleAssigned", {"role": &"crew"})
			model.fold(&"PhaseChanged", {"phase": &"end", "end_tick": 160})
			model.fold(&"MatchEnded", {"side": end_winner})
			ui.end.show_reason(end_reason, end_round_seconds)
			ui.show_screen(GameFlow.Screen.END)
		Preview.ESC:
			if esc_in_round:
				fold_round(model, false)
			ui.show_screen(GameFlow.Screen.ROUND if esc_in_round else GameFlow.Screen.LOBBY)
			ui.open_esc(hosting, model)
			if esc_tab != EscMenuState.Tab.RESUME:
				# Pressing Resume would close the menu: in the round it is the tab Esc opens on.
				ui.esc.press(esc_tab)
			ui.esc.voice.show_facts(fake_voice(not voice_unavailable))
			if controls_clash:
				var key := InputEventKey.new()
				key.physical_keycode = KEY_V
				ui.esc.controls.controls.bind(&"task_screen", key)
				ui.esc.controls.refresh()
		Preview.ROUND, Preview.TASKS:
			fold_round(model, true)
			ui.show_screen(GameFlow.Screen.ROUND)
			ui.show_tasks(preview == Preview.TASKS)
			var local := HudText.Local.new()
			local.stamina = 62.0
			local.hint = "E: pick up Knife"
			ui.refresh_round(model, mode, 100, local)
	ui.refresh(model, mode, 100, hosting)


## The connecting screen in `state` as the handoff's samples draw it (#494): a code join 4 s in,
## a Direct one 2 s in, joined 9 s in with the host's lobby name; a failure, the version one with
## both versions. Returns the screen to show.
static func show_s3_state(screen: ConnectingScreen, state: StringName) -> GameFlow.Screen:
	match state:
		&"finding":
			screen.show_join(PREVIEW_CODE, JoinProgress.Step.FINDING)
			screen.set_elapsed(4)
		&"connecting-direct":
			screen.show_join("", JoinProgress.Step.CONNECTING)
			screen.set_elapsed(2)
		&"joined":
			screen.show_join(PREVIEW_CODE, JoinProgress.Step.JOINED)
			screen.set_lobby("", "Olena")
			screen.set_elapsed(9)
		_:
			var versions := PackedStringArray([PREVIEW_HOST_VERSION, PREVIEW_OWN_VERSION])
			screen.show_failure(state, versions)
			return GameFlow.Screen.FAILURE
	return GameFlow.Screen.CONNECTING


## The Voice tab's facts (M5-6): two microphones besides the Windows default, a headset picked,
## voice activity at the default threshold with the meter over it, and the debug tools.
static func fake_voice(available: bool) -> VoicePanel.Shown:
	var shown := VoicePanel.Shown.new()
	shown.available = available
	shown.devices = PackedStringArray(
		[VoiceMicrophone.DEFAULT_DEVICE, "Headset Microphone (USB)", "Microphone Array (Realtek)"]
	)
	shown.device = "Headset Microphone (USB)"
	shown.peak = 0.23
	for bus: StringName in UserSettings.VOLUMES:
		shown.volumes[bus] = UserSettings.default_db(bus)
	shown.debug = true
	return shown


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
