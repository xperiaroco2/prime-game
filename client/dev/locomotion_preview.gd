extends Node3D
## A preview of other players' eight-direction locomotion for `tools\run.cmd shot` (#1334, art
## #196, ARCHITECTURE §4.7.53): remote bodies wearing the art's character (slice_m1, the game's
## case), each drawn as AvatarViews draws it: a pose with its aim, then AvatarClips' plan against
## the lagging body yaw. The back row runs the directions on the spot: forward, a front diagonal
## (blended between Jog_Fwd and Strafe_Left until the alien GLBs bring Jog_Fwd_Left), left, right,
## a back diagonal and backward (the back family: Jog_Bwd alone on slice_m1). The front row,
## nearer the camera, looks: a head shake (the aim 40 degrees left of the standing body: inside
## the 45-degree dead zone the body stays and the head turns), a nod down and a nod up, and an
## aim past the zone (the body follows to 45 degrees behind it). Dev only: nothing here reaches
## the game.

const MODE := "res://content/modes/base_mode.tres"
const BODY := preload("res://client/player/remote_player_body.tscn")
## The runners' yaw: three-quarters towards the camera (the lookers stand facing it).
const FACING := PI + deg_to_rad(25.0)
const JOG_MPS := 4.5

## [label, heading in degrees (positive: the body's left)] of the back row's moves (the runners).
const MOVES: Array[Array] = [
	["forward", 0.0],
	["front diagonal", 45.0],
	["left", 90.0],
	["right", -90.0],
	["back diagonal", 135.0],
	["backward", 180.0],
]
## [label, aim yaw off the body in degrees, pitch in degrees] of the front row's looks (the lookers,
## nearer the camera).
const LOOKS: Array[Array] = [
	["shake 40", 40.0, 0.0],
	["nod down", 0.0, -35.0],
	["nod up", 0.0, 40.0],
	["aim 80: body follows", 80.0, 0.0],
]

var _rules: PlayerRules
var _character: CharacterSet
var _runners: Array[RemotePlayerBody] = []
var _plans: Array[AvatarClips.Plan] = []


func _ready() -> void:
	_rules = (load(MODE) as GameMode).player_rules
	_character = CharacterSet.load_default()
	_add_floor()
	_add_light()
	for index: int in MOVES.size():
		var at := Vector3((index - (MOVES.size() - 1) * 0.5) * 1.4, 0.0, -0.8)
		var move: Array = MOVES[index]
		_add_runner(at, index, deg_to_rad(move[1] as float), move[0] as String)
	for index: int in LOOKS.size():
		var at := Vector3((index - (LOOKS.size() - 1) * 0.5) * 1.5, 0.0, 2.0)
		var look: Array = LOOKS[index]
		var yaw := deg_to_rad(look[1] as float)
		_add_looker(at, index, yaw, deg_to_rad(look[2] as float), look[0] as String)
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(-20.0), 0.0, 0.0)), Vector3(0.0, 2.9, 5.6)
	)
	camera.make_current()


func _process(_delta: float) -> void:
	for index: int in _runners.size():
		_runners[index].apply_plan(_plans[index])


## A body at `at` running the move `heading` radians off its forward, at the jog's speed.
func _add_runner(at: Vector3, colour: int, heading: float, label: String) -> void:
	var body := _add_body(at, colour, label)
	_set_pose(body, at, FACING, 0.0)
	var state := AvatarClips.State.new()
	state.yaw = body.body_yaw
	var local := Vector3(-sin(heading), 0.0, -cos(heading))
	state.drawn_move = Basis(Vector3.UP, body.body_yaw) * local * JOG_MPS
	var plan := AvatarClips.plan(state, _rules.walk_speed_mps, _rules.sprint_speed_mps)
	_runners.append(body)
	_plans.append(plan)


## A standing body at `at` whose aim turns `yaw_off` radians off where it stood, pitched `pitch`.
func _add_looker(at: Vector3, colour: int, yaw_off: float, pitch: float, label: String) -> void:
	var body := _add_body(at, colour + MOVES.size(), label)
	_set_pose(body, at, PI, 0.0)
	_set_pose(body, at, PI + yaw_off, pitch)
	var state := AvatarClips.State.new()
	state.yaw = body.body_yaw
	body.apply_plan(AvatarClips.plan(state, _rules.walk_speed_mps, _rules.sprint_speed_mps))


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


func _set_pose(body: RemotePlayerBody, at: Vector3, yaw: float, pitch: float) -> void:
	var pose := SnapshotBuffer.Pose.new()
	pose.position = at
	pose.yaw = yaw
	pose.pitch = pitch
	body.set_pose(pose)


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
