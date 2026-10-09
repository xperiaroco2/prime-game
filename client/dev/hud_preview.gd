extends Node3D
## A preview of the round HUD for `tools\run.cmd shot` (#489; the M4 ADR's §6): the UI handoff's
## states (prime-game-ui `ui-0.4.0` `docs/handoff/s07-hud.md`) over a lit greybox room, drawn by
## the game's GameUi from a fake ClientModel and HudText.Local, as a host would send them:
## - `empty`: an Engineer, nothing carried, the crosshair on a package within reach;
## - `pack`: carrying a package with both hands (the hand slot widens);
## - `tired`: stamina at 0.18; `hurt`: health at 0.22;
## - `mate`: a dissident with a knife on the belt looking at a teammate (the name plate's mark);
## - `raising`: holding Interact on a downed teammate (the raise bar in place of Aim);
## and the handoff s09's (`docs/handoff/s09-downed.md`, #497), drawn by the game's LifeScreen from
## LifeHud over the same HUD:
## - `downed`: 3 s into the mode's 10 s knockdown (the bleed-out bar at 0.7, "0:07"), the mic off;
## - `holding`: the same, the give-up key held 0.45 s of its 1 s;
## - `raised`: the teammate raising the player, 0.6 of the way;
## - `dead`: spectating the teammate, 6 s after the death (back in 0:24);
## - `back`: respawned this tick, empty hands, stamina full: the protection chip counts 3.
## The samples are the handoff's: 07:22 left, health 0.8, stamina 0.9, the microphone on. Dev only:
## nothing here reaches the game.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
## The handoff's time left (07:22) before the fake match clock ends.
const TIME_LEFT_S := 442
const NOW := 100
## The teammate, its spot in front of the camera and a package lying within reach.
const MATE := 3
const MATE_AT := Vector3(-1.4, 0.0, -4.0)
const LYING := 31
const TICK_USEC := 50000

@export_enum(
	"empty",
	"pack",
	"tired",
	"hurt",
	"mate",
	"raising",
	"downed",
	"holding",
	"raised",
	"dead",
	"back"
)
var state := "empty"
## The language of the words (Languages.ENGLISH or UKRAINIAN) and the large-text theme (#289).
@export var language := Languages.ENGLISH
@export var large_text := false

var _now := 1000000
var _model: ClientModel
var _avatars: AvatarViews


func _ready() -> void:
	TranslationServer.set_locale(language)
	var mode := load(MODE) as GameMode
	var rules := mode.player_rules
	_add_room()
	_model = _fake_round(mode)
	_avatars = AvatarViews.new()
	_avatars.model = _model
	_avatars.buffer = SnapshotBuffer.new()
	_avatars.rules = rules
	_avatars.clock = func() -> int: return _now
	add_child(_avatars)
	if state == "mate":
		for tick: int in 6:
			_snapshot(tick + 1)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.0, rules.eye_height_m, 0.0)
	camera.rotation = Vector3(deg_to_rad(-4.0), 0.0, 0.0)
	camera.make_current()
	var ui := GameUi.new()
	add_child(ui)
	ui.set_large_text(large_text)
	ui.plates.avatars = _avatars
	ui.show_screen(GameFlow.Screen.ROUND)
	ui.refresh_round(_model, mode, NOW, _local())
	ui.life.show_hud(_life(mode))


## The fake round of `state`, seen by Player1 (peer 1).
func _fake_round(mode: GameMode) -> ClientModel:
	var model := Preview.fake_model(mode, true)
	var end_tick := NOW + TIME_LEFT_S * Ticks.RATE
	model.fold(&"PhaseChanged", {"phase": &"round", "end_tick": end_tick})
	var dissident := state in ["mate", "dead"]
	model.fold(&"RoleAssigned", {"role": &"dissident" if dissident else &"crew"})
	if dissident:
		model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([1, MATE])})
	model.roster[MATE].name = "Тарас" if language == Languages.UKRAINIAN else "Taras"
	var health := 22000 if state == "hurt" else 80000
	if state == "back":
		health = mode.player_rules.health * Ticks.THOUSANDTHS
	model.fold(&"SelfStatus", {"health": health, "stamina": 90000, "sprint_available": true})
	var at := Vector3(0.4, 0.0, -1.5)
	model.fold(&"ItemSpawned", {"item": LYING, "kind": &"package", "position": at})
	model.fold(&"ItemSpawned", {"item": Preview.KNIFE, "kind": &"knife", "position": at})
	match state:
		"pack":
			model.fold(&"ItemPickedUp", {"peer": 1, "item": LYING})
		"mate":
			model.fold(&"ItemPickedUp", {"peer": 1, "item": Preview.KNIFE})
			model.fold(&"Swapped", {"peer": 1})
		"dead":
			model.fold(&"ItemPickedUp", {"peer": MATE, "item": LYING})
	for event: Array in _life_events(mode):
		model.fold(event[1] as StringName, event[2] as Dictionary)
	return model


func _local() -> HudText.Local:
	var local := HudText.Local.new()
	local.stamina = 18.0 if state == "tired" else 90.0
	if state == "back":
		local.stamina = _full_stamina()
	# Nobody hears a downed or dead player (VoiceSender.live()).
	local.mic = state not in ["downed", "holding", "raised", "dead"]
	if state in ["empty", "tired", "hurt"]:
		local.aim = LYING
	if state == "raising":
		local.raising = 0.6
	return local


## The own life's events of `state`, [seconds before NOW, name, fields] each (the handoff's
## samples: the knockdown 3 s ago, the raise 0.6 of the way, the death 6 s ago, the respawn now).
func _life_events(mode: GameMode) -> Array[Array]:
	var knocked := {"peer": 1, "position": Vector3(3, 0, 2)}
	var raise := {"raiser": MATE, "target": 1}
	var raise_s := LifeCountdowns.raise_seconds_of(mode)
	match state:
		"downed", "holding":
			return [[3.0, &"KnockedDown", knocked]]
		"raised":
			return [[3.0, &"KnockedDown", knocked], [0.6 * raise_s, &"RaiseStarted", raise]]
		"dead":
			return [[6.0, &"Died", knocked]]
		"back":
			return [[30.0, &"Died", knocked], [0.0, &"Respawned", knocked]]
	return []


## What the downed, dead and respawn screen shows in `state` (LifeHud, as LifeView feeds it).
func _life(mode: GameMode) -> LifeHud.Shown:
	var countdowns := LifeCountdowns.new(mode.player_rules, LifeCountdowns.raise_seconds_of(mode))
	for event: Array in _life_events(mode):
		var ago: float = event[0]
		var tick := NOW - ago * Ticks.RATE
		countdowns.on_event(event[1] as StringName, event[2] as Dictionary, 1, tick)
	var local := LifeHud.Local.new()
	local.read_keys()
	if state == "holding":
		local.give_up_held_s = 0.45
	if state == "dead":
		local.watching = MATE
	return LifeHud.of(_model, countdowns, NOW, local)


## The mode's full stamina in points.
func _full_stamina() -> float:
	return float((load(MODE) as GameMode).player_rules.stamina)


## The teammate at its spot, facing the camera, in the snapshot of `tick`.
func _snapshot(tick: int) -> void:
	var avatars := {
		MATE: {"position": MATE_AT, "velocity": Vector3.ZERO, "facing": Vector3.BACK},
	}
	_now += TICK_USEC
	_model.fold_snapshot({"tick": tick, "avatars": avatars})
	_avatars.buffer.add(tick, avatars, _now)


## A lit greybox room: a floor and three walls (layout, not a level; colours of the dev previews).
func _add_room() -> void:
	_add_box(Vector3(0.0, -0.05, -5.0), Vector3(14.0, 0.1, 14.0), Color(0.36, 0.34, 0.3))
	_add_box(Vector3(0.0, 1.5, -10.0), Vector3(14.0, 3.0, 0.2), Color(0.72, 0.66, 0.58))
	_add_box(Vector3(-5.0, 1.5, -5.0), Vector3(0.2, 3.0, 14.0), Color(0.64, 0.6, 0.54))
	_add_box(Vector3(5.0, 1.5, -5.0), Vector3(0.2, 3.0, 14.0), Color(0.64, 0.6, 0.54))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, 2.7, -4.0)
	lamp.omni_range = 12.0
	add_child(lamp)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(30.0), 0.0)
	sun.light_energy = 0.4
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.2, 0.2, 0.24)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	add_child(environment)


## A box on the world layer (the plates' ray meets it), at `at` of `size` and `colour`.
func _add_box(at: Vector3, size: Vector3, colour: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)
