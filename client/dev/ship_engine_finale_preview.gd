extends Node3D
## A preview of the ship engine's finish (#1502, ARCHITECTURE §9.5.27) for `tools\run.cmd shot`:
## the estate's ship room (`levels/estate/rooms/ship.tscn`, the art ship, read only) with the
## engine's console placed at its marker, driven by ShipEngineViews from a fake ClientModel. The
## console's done ZoneProgress (the engine's last stage) starts the roar's frame, so the flame
## from the nozzles and the light show play; the preview runs them `seconds` in with fixed frames.
## `inside` puts the camera in the hall facing the hologram's show, else behind the stern facing
## the nozzles. Dev only, nothing here reaches the game.

const Preview := preload("res://client/dev/screen_preview.gd")
const Kit := preload("res://client/dev/preview_kit.gd")
const ROOM := "res://levels/estate/rooms/ship.tscn"
const CONSOLE := 1
const NOW := 2000
const FRAME_S := 0.05

## Seconds into the finish when the picture is taken.
@export var seconds := 1.0
@export var inside := false


func _ready() -> void:
	var mode := load(Preview.MODE) as GameMode
	var model := ClientModel.new(mode)
	model.own_peer = 1
	_fold(model, PhaseChangedEvent.new(&"round", NOW + 6000))
	var room := (load(ROOM) as PackedScene).instantiate() as Node3D
	room.name = "Level"
	add_child(room)
	_build_sky()
	var console := room.find_child("EngineConsole01", true, false) as Node3D
	Kit.place(model, CONSOLE, &"engine_console", console.global_position)
	var views := ShipEngineViews.new()
	views.model = model
	views.mode = mode
	views.host_tick = func() -> int: return NOW
	add_child(views)
	views.level = room
	views._process(0.0)
	model.fold(
		&"ZoneProgress",
		{"station": CONSOLE, "ticks": 600, "needed": 600, "counting": false, "tick": NOW}
	)
	views._process(0.0)
	for i in roundi(seconds / FRAME_S):
		views._process(FRAME_S)
	var camera := Camera3D.new()
	add_child(camera)
	if inside:
		camera.look_at_from_position(Vector3(-2.4, 1.8, -3.4), Vector3(0, 3.0, 0.6))
	else:
		camera.look_at_from_position(Vector3(11.0, 5.0, 24.0), Vector3(0, 2.3, 12.0))
	camera.current = true


## Folds `event` into `model`, as the session does with what it decodes.
func _fold(model: ClientModel, event: MatchEvent) -> void:
	model.fold(event.event_name(), event.to_dict())


## A dusk sky and a low sun, so the flames and the lights show (the room frees the art's own).
func _build_sky() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.35, 0.8, 0)
	sun.light_energy = 0.4
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.14, 0.22)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.25, 0.27, 0.33)
	environment.environment.glow_enabled = true
	add_child(environment)
