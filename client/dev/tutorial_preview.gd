extends Node3D
## A preview of the tutorial's screens (#492, TutorialScreen) for `tools\run.cmd shot`: the
## tutorial room (levels/tutorial/) seen from its start spot, the round HUD without the timer and
## the role (#489), and the s1 handoff's states: `invite` (the first launch's invite over the
## room), `step` (lesson 2, its first instruction), `step-keys` (lesson 1's row of keycaps) and
## `step-howto` (lesson 5's second instruction, the round «?»; the handoff draws neither the map
## nor the HUD under it), in English or Ukrainian, at the default or the large text size. Dev
## only: nothing here reaches the game.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/tutorial_mode.tres"
const ROOM := "res://levels/tutorial/tutorial.tscn"
const LESSONS := "res://content/tutorial/tutorial.tres"
const NOW := 100
## The camera at the room's start spot, at eye height, turned to the room (layout of a shot).
const LOOK_FROM := Vector3(2.0, 0.0, 5.0)
const LOOK_AT := Vector3(-1.0, 1.0, -2.0)

@export_enum("invite", "step", "step-keys", "step-howto") var state := "invite"
@export var language := Languages.ENGLISH
@export var large_text := false


func _ready() -> void:
	TranslationServer.set_locale(language)
	var mode := load(MODE) as GameMode
	add_child((load(ROOM) as PackedScene).instantiate())
	# The greybox room brings no light: the dev previews' grey ambient and one lamp.
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.55)
	add_child(environment)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, 2.6, 0.0)
	lamp.omni_range = 14.0
	add_child(lamp)
	var camera := Camera3D.new()
	add_child(camera)
	var eye := LOOK_FROM + Vector3(0.0, mode.player_rules.eye_height_m, 0.0)
	camera.look_at_from_position(eye, LOOK_AT)
	camera.make_current()
	var model := Preview.fake_model(mode, true)
	model.fold(&"PhaseChanged", {"phase": &"lessons", "end_tick": -1})
	model.fold(&"SelfStatus", {"health": 80000, "stamina": 90000, "sprint_available": true})
	var ui := GameUi.new()
	add_child(ui)
	ui.set_large_text(large_text)
	ui.set_tutorial(true)
	if state == "invite":
		ui.tutorial.open_invite()
	ui.show_screen(GameFlow.Screen.ROUND)
	var local := HudText.Local.new()
	local.stamina = float(mode.player_rules.stamina)
	local.mic = true
	ui.refresh_round(model, mode, NOW, local)
	ui.hud.visible = state not in ["invite", "step-howto"]
	var lessons := load(LESSONS) as TutorialLessons
	# The lesson and step each state draws; the invite's none.
	var places: Dictionary[String, Vector2i] = {
		"step": Vector2i(2, 1), "step-keys": Vector2i(1, 1), "step-howto": Vector2i(5, 2)
	}
	var at: Vector2i = places.get(state, Vector2i.ZERO)
	var done: Array[bool] = []
	for number in range(1, lessons.lessons.size() + 1):
		done.append(number < at.x)
	ui.tutorial.show_lessons(lessons, at.x, at.y, done)
