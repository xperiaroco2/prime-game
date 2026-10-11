extends "res://client/dev/hud_preview.gd"
## A preview of the lobby HUD for `tools\run.cmd shot` (#495; the M4 ADR's §6): the UI handoff's
## states (prime-game-ui `ui-0.4.0` `docs/handoff/s04-lobby.md`) over the round HUD preview's lit
## greybox room, drawn by the game's GameUi from a fake ClientModel, as a host would send it. The
## handoff's lobby: Olena hosts (peer 1), Taras (2), the third player (3) and Marko (4); Taras
## stands in view with his name plate. Seen by a code joiner (peer 3), or with `hosting` by Olena:
## - `wait`: three of four ready, the own player not; the code K7Q2XR;
## - `count`: everyone ready, the countdown at 5;
## - `short`: Marko gone and the host saying one more player of four is needed (its players_few,
##   #548; the handoff's sample, not a decision): one more player to start;
## - `code-waiting`: the host alone before the code service made the room (always hosting; four
##   needed as in `short`: three more to start);
## - `direct`: `wait` joined directly, with no code.
## The microphone on. Dev only: nothing here reaches the game.

## The players the host's shortfall counts against in `short` and `code-waiting`: the handoff's
## sample, not a decision.
const SHORT_MIN_PLAYERS := 4
const CODE := "K7Q2XR"
## Taras, in view to the right (the handoff's plate sits right of the centre).
const TARAS := 2
const TARAS_AT := Vector3(1.4, 0.0, -4.0)

@export_enum("wait", "count", "short", "code-waiting", "direct") var lobby_state := "wait"
## The host's own view (its own row reads `player.you`) instead of a code joiner's.
@export var hosting := false


func _ready() -> void:
	TranslationServer.set_locale(language)
	var mode := load(MODE) as GameMode
	var rules := mode.player_rules
	_add_room()
	_model = _fake_lobby(mode)
	_avatars = AvatarViews.new()
	_avatars.model = _model
	_avatars.buffer = SnapshotBuffer.new()
	_avatars.rules = rules
	_avatars.clock = func() -> int: return _now
	add_child(_avatars)
	if _model.roster.has(TARAS):
		for tick: int in 6:
			_lobby_snapshot(tick + 1)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.0, rules.eye_height_m, 0.0)
	camera.rotation = Vector3(deg_to_rad(-4.0), 0.0, 0.0)
	camera.make_current()
	var ui := GameUi.new()
	add_child(ui)
	ui.set_large_text(large_text)
	ui.plates.avatars = _avatars
	ui.show_screen(GameFlow.Screen.LOBBY)
	var waiting := lobby_state == "code-waiting"
	ui.lobby_hud.show_code("" if waiting or lobby_state == "direct" else CODE, false, waiting)
	ui.lobby_hud.show_mic(true)
	ui.refresh(_model, mode, NOW, _hosts())


func _hosts() -> bool:
	return hosting or lobby_state == "code-waiting"


## The handoff's lobby in `lobby_state`.
func _fake_lobby(mode: GameMode) -> ClientModel:
	var uk := language == Languages.UKRAINIAN
	var names: Array[String] = ["Olena", "Taras", "Ivan", "Marko"]
	if uk:
		names = ["Олена", "Тарас", "Іван", "Марко"]
	var own := 1 if _hosts() else 3
	var count := 4
	if lobby_state == "short":
		count = 3
	elif lobby_state == "code-waiting":
		count = 1
	var roster: Array[Dictionary] = []
	for index in count:
		var peer := index + 1
		var is_ready := peer != own or lobby_state == "count"
		roster.append({"peer": peer, "name": names[index], "ready": is_ready, "colour": index})
	var model := ClientModel.new(mode)
	var welcome := WelcomeEvent.new(own, Vector3.ZERO, 1)
	welcome.roster.assign(roster)
	welcome.settings = mode.default_settings()
	welcome.map = Preview.MAP
	welcome.phase = &"lobby"
	model.fold(&"Welcome", welcome.to_dict())
	if count < SHORT_MIN_PLAYERS:
		# The host's SettingsChanged (#548): players_few, `count` the players still missing.
		var missing := SHORT_MIN_PLAYERS - count
		var bounds := {&"count": missing, &"min": SHORT_MIN_PLAYERS, &"max": mode.max_players}
		var players_few := {"id": &"players_few", "ids": PackedStringArray(), "numbers": bounds}
		var changed := {
			"settings": model.settings,
			"id_sets": model.id_sets,
			"map": model.map,
			"shortfalls": [players_few],
			"lobby_name": "",
		}
		model.fold(&"SettingsChanged", changed)
	if lobby_state == "count":
		model.fold(&"PhaseChanged", {"phase": &"countdown", "end_tick": NOW + 5 * Ticks.RATE})
	return model


## Taras at his spot, facing the camera, in the snapshot of `tick`.
func _lobby_snapshot(tick: int) -> void:
	var avatars := {
		TARAS: {"position": TARAS_AT, "velocity": Vector3.ZERO, "facing": Vector3.BACK},
	}
	_now += TICK_USEC
	_model.fold_snapshot({"tick": tick, "avatars": avatars})
	_avatars.buffer.add(tick, avatars, _now)
