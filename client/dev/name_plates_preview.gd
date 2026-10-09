extends Node3D
## A preview of the name plates for `tools\run.cmd shot` (#257; the M4 ADR's §6): the round seen
## by Player1, a dissident whose teammate is Євген (peer 3). Player2 stands in front with a plain
## plate; Євген further back with the teammate mark; Olena's head shows over a wall that hides
## her eyes, so she has no plate; Far stands in the open about 14 m away, beyond the 10 m range,
## with none. The bodies are drawn by a real AvatarViews from fake snapshots and the plates by
## the game's NamePlates, rays and all. Dev only: nothing here reaches the game.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
const MATE := 3
const WALLED := 4
const FAR := 5
const SPOTS: Dictionary[int, Vector3] = {
	2: Vector3(-1.6, 0.0, -4.5),
	MATE: Vector3(1.2, 0.0, -6.5),
	WALLED: Vector3(4.0, 0.0, -6.5),
	FAR: Vector3(-6.5, 0.0, -12.0),
}
## The wall in front of Olena: its middle and size, 1.65 m high, under her 1.8 m capsule's top and
## over her 1.6 m eyes.
const WALL_AT := Vector3(4.0, 0.825, -5.0)
const WALL_SIZE := Vector3(3.0, 1.65, 0.3)
const TICK_USEC := 50000

var _now := 1000000
var _model: ClientModel
var _avatars: AvatarViews


func _ready() -> void:
	TranslationServer.set_locale(Languages.ENGLISH)
	var mode := load(MODE) as GameMode
	var rules := mode.player_rules
	_add_floor()
	_add_wall()
	_add_light()
	_model = Preview.fake_model(mode, true)
	Preview.fold_round(_model)
	_model.roster[MATE].name = "Євген"
	_model.fold(&"PlayerJoined", {"peer": WALLED, "name": "Olena", "spot": SPOTS[WALLED]})
	_model.fold(&"PlayerJoined", {"peer": FAR, "name": "Far", "spot": SPOTS[FAR]})
	_avatars = AvatarViews.new()
	_avatars.model = _model
	_avatars.buffer = SnapshotBuffer.new()
	_avatars.rules = rules
	_avatars.clock = func() -> int: return _now
	add_child(_avatars)
	for i: int in 6:
		_snapshot(i + 1)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.0, rules.eye_height_m, 0.0)
	camera.rotation = Vector3(deg_to_rad(-4.0), 0.0, 0.0)
	camera.make_current()
	var ui := GameUi.new()
	add_child(ui)
	ui.reads_device_input = false
	ui.plates.avatars = _avatars
	ui.show_screen(GameFlow.Screen.ROUND)
	var local := HudText.Local.new()
	local.stamina = 62.0
	ui.refresh_round(_model, mode, 100, local)


## Every player at its spot, facing the camera, in the snapshot of `tick`.
func _snapshot(tick: int) -> void:
	var avatars := {}
	for peer: int in SPOTS:
		avatars[peer] = {"position": SPOTS[peer], "velocity": Vector3.ZERO, "facing": Vector3.BACK}
	_now += TICK_USEC
	_model.fold_snapshot({"tick": tick, "avatars": avatars})
	_avatars.buffer.add(tick, avatars, _now)


func _add_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.34, 0.3)
	plane.material = material
	floor_mesh.mesh = plane
	add_child(floor_mesh)


## A wall on the world layer (Godot's default layer 1, as a level's), which the plates' ray meets.
func _add_wall() -> void:
	var wall := StaticBody3D.new()
	wall.position = WALL_AT
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = WALL_SIZE
	shape.shape = box
	wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = WALL_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.62, 0.58, 0.52)
	box_mesh.material = material
	mesh.mesh = box_mesh
	wall.add_child(mesh)
	add_child(wall)


func _add_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(30.0), 0.0)
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.6, 0.66)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(environment)
