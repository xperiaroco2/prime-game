extends Node3D
## A preview of the ship's match console (#1604; prime-game-ui `ui-2.5.4` s04 `console-host` and
## `console-guest`) for `tools\run.cmd shot`, from a fake ClientModel of the base mode's lobby on
## its player map (the Estate in M8): Olena hosts (peer 1), Taras (2) and Ivan (3); seen by Olena
## with `hosting`, else by Ivan, a code joiner. `view` picks the frame:
## - `screen`: the console's 960 x 540 screen centred in the frame, as the handoff's review page
##   draws it;
## - `world`: the lobby hall with the console where the level puts it, seen from a player standing
##   in front of it at the eye's height (the sun and the sky are the preview's own);
## - `spawn`: the same from the lobby's first spawn marker, where the first player (the host, or
##   the player alone in the own ship) starts.
## Dev only: nothing here reaches the game.

const LOBBY := "res://levels/lobby/lobby.tscn"
const MODE := "res://content/modes/base_mode.tres"
const CODE := "K7Q2XR"
## The eye's height and its distance from the screen in `world`, metres.
const EYE_M := 1.6
const BACK_M := 1.6
## The lobby's first spawn marker (LobbyPlayer01 of levels/lobby/lobby.tscn).
const SPAWN := Vector3(-9.0, 0.0, 2.5)

@export_enum("screen", "world", "spawn") var view := "screen"
## Olena's own view (the host) instead of Ivan's.
@export var hosting := true
## The language of the words (Languages.ENGLISH or UKRAINIAN).
@export var language := Languages.ENGLISH


func _ready() -> void:
	TranslationServer.set_locale(language)
	var mode := load(MODE) as GameMode
	var model := _fake_lobby(mode)
	if view != "screen":
		_world(mode, model)
		return
	var frame := Control.new()
	frame.theme = GameUi.THEME
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	var ground := Panel.new()
	ground.theme_type_variation = &"ToyBackdropFullScreen"
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(ground)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(centre)
	var screen := ConsoleScreen.new()
	centre.add_child(screen)
	_show(screen, mode, model)


func _world(mode: GameMode, model: ClientModel) -> void:
	_light()
	var level := (load(LOBBY) as PackedScene).instantiate()
	add_child(level)
	var console := MatchConsole.new()
	console.model = model
	add_child(console)
	console.level = level
	_show(console.screen, mode, model)
	var at := console.quad.global_transform
	var eye := at.origin + at.basis.z * BACK_M
	if view == "spawn":
		eye = SPAWN
	eye.y = EYE_M
	var camera := Camera3D.new()
	add_child(camera)
	camera.look_at_from_position(eye, at.origin)
	camera.current = true


func _show(screen: ConsoleScreen, mode: GameMode, model: ClientModel) -> void:
	screen.set_mode(mode)
	screen.refresh(model, hosting, hosting, true)
	screen.show_code(JoinProgress.code_text(CODE, false, true), CODE)


func _fake_lobby(mode: GameMode) -> ClientModel:
	var uk := language == Languages.UKRAINIAN
	var names: Array[String] = ["Olena", "Taras", "Ivan"]
	if uk:
		names = ["Олена", "Тарас", "Іван"]
	var roster: Array[Dictionary] = []
	for index in names.size():
		roster.append({"peer": index + 1, "name": names[index], "ready": false, "colour": index})
	var model := ClientModel.new(mode)
	var welcome := WelcomeEvent.new(1 if hosting else 3, Vector3.ZERO, 1)
	welcome.roster.assign(roster)
	welcome.settings = mode.default_settings()
	welcome.map = mode.player_maps()[0]
	welcome.phase = &"lobby"
	model.fold(&"Welcome", welcome.to_dict())
	return model


func _light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.65, 0.75)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(environment)
