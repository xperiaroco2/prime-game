extends Node3D
## A preview of the ten body colours for `tools\run.cmd shot` (#551): ten players in a row, peer
## n + 1 in colour n (BodyColours, the delivery circles' colours), drawn by a real AvatarViews
## from fake snapshots and the roster's colours; the last two lie downed, so the lying capsule
## shows its colour too. Dev only: nothing here reaches the game.

const MODE := "res://content/modes/base_mode.tres"
const TICK_USEC := 50000
## The gap between two players, in metres, and how far from the camera the row stands.
const GAP_M := 1.1
const ROW_Z := -7.0
## The players who lie downed.
const DOWNED: Array[int] = [9, 10]

var _now := 1000000
var _model: ClientModel
var _avatars: AvatarViews


func _ready() -> void:
	var mode := load(MODE) as GameMode
	var rules := mode.player_rules
	_add_floor()
	_add_light()
	_model = ClientModel.new(mode)
	_model.own_peer = 99
	for index: int in PlayerColours.COUNT:
		var peer := index + 1
		var fields := {"peer": peer, "name": "P%d" % peer, "spot": _spot(peer), "colour": index}
		_model.fold(&"PlayerJoined", fields)
	for peer: int in DOWNED:
		_model.fold(&"KnockedDown", {"peer": peer, "position": _spot(peer)})
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
	camera.position = Vector3(0.0, 2.2, 0.0)
	camera.rotation = Vector3(deg_to_rad(-12.0), 0.0, 0.0)
	camera.make_current()


func _spot(peer: int) -> Vector3:
	return Vector3((peer - 5.5) * GAP_M, 0.0, ROW_Z)


## Every player at its spot, facing the camera, in the snapshot of `tick`.
func _snapshot(tick: int) -> void:
	var avatars := {}
	for peer: int in range(1, PlayerColours.COUNT + 1):
		avatars[peer] = {
			"position": _spot(peer),
			"velocity": Vector3.ZERO,
			"facing": Vector3.BACK,
			"downed": DOWNED.has(peer),
		}
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
