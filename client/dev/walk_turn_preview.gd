extends Node3D
## A preview of #1712 for `tools\run.cmd shot`: remote bodies wearing the art's character, each
## drawn as AvatarViews draws it (set_pose with the drawn move, then AvatarClips' plan against the
## body's yaw). All three aim 40 degrees left of where they stood; left to right: standing (inside
## the 45-degree dead zone the body stays and the head turns), 0.1 s into a slow walk the way it
## looks (the body starting to turn), and 1 s into it (the body on the walk, Walk playing). The
## walk runs on the spot: only the drawn move is fed. Dev only: nothing here reaches the game.

const MODE := "res://content/modes/base_mode.tres"
const BODY := preload("res://client/player/remote_player_body.tscn")
## Where the bodies stood: facing three-quarters toward the camera.
const STOOD := PI + deg_to_rad(25.0)
const AIM_OFF := deg_to_rad(40.0)
## A slow walk, metres a second (under AvatarClips.WALK_UP_TO_MPS).
const WALK_MPS := 1.0
const FRAME_S := 1.0 / 60.0
## [label, seconds walked] of each body, left to right.
const WALKS: Array[Array] = [
	["standing, aim 40", 0.0],
	["walking 0.1 s", 0.1],
	["walking 1 s", 1.0],
]

var _rules: PlayerRules
var _character: CharacterSet
var _bodies: Array[RemotePlayerBody] = []
var _plans: Array[AvatarClips.Plan] = []


func _ready() -> void:
	_rules = (load(MODE) as GameMode).player_rules
	_character = CharacterSet.load_default()
	_add_floor()
	_add_light()
	for index: int in WALKS.size():
		var at := Vector3((index - (WALKS.size() - 1) * 0.5) * 1.6, 0.0, 0.0)
		var walk: Array = WALKS[index]
		_add_walker(at, index, walk[1] as float, walk[0] as String)
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(-15.0), 0.0, 0.0)), Vector3(0.0, 2.2, 4.2)
	)
	camera.make_current()


func _process(_delta: float) -> void:
	for index: int in _bodies.size():
		_bodies[index].apply_plan(_plans[index])


## A body at `at` that stood facing STOOD, aims AIM_OFF left of it and walks `seconds` the way it
## aims, frame by frame.
func _add_walker(at: Vector3, colour: int, seconds: float, label: String) -> void:
	var body := _add_body(at, colour, label)
	_set_pose(body, at, STOOD, Vector3.ZERO, 0.0)
	var aim := STOOD + AIM_OFF
	_set_pose(body, at, aim, Vector3.ZERO, 0.0)
	var move := Vector3.ZERO
	if seconds > 0.0:
		move = Vector3(-sin(aim), 0.0, -cos(aim)) * WALK_MPS
	for frame: int in roundi(seconds / FRAME_S):
		_set_pose(body, at, aim, move, FRAME_S)
	var state := AvatarClips.State.new()
	state.yaw = body.body_yaw
	state.drawn_move = move
	_bodies.append(body)
	_plans.append(AvatarClips.plan_by(state, _rules, body.extra_clips()))


func _add_body(at: Vector3, colour: int, label: String) -> RemotePlayerBody:
	var body := BODY.instantiate() as RemotePlayerBody
	body.rules = _rules
	add_child(body)
	body.set_character(_character)
	body.set_colour(BodyColours.of(colour))
	var tag := Label3D.new()
	tag.text = label
	tag.font_size = 22
	tag.no_depth_test = true
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = at + Vector3(0.0, 1.95, 0.0)
	add_child(tag)
	return body


func _set_pose(
	body: RemotePlayerBody, at: Vector3, yaw: float, move: Vector3, delta: float
) -> void:
	var pose := SnapshotBuffer.Pose.new()
	pose.position = at
	pose.yaw = yaw
	body.set_pose(pose, move, delta)


func _add_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
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
