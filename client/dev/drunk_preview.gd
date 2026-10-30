extends Node3D
## A preview of the drunk camera's sway for `tools\run.cmd shot` (#1391; ARCHITECTURE §4.7.6
## "Drunk"): the first-person view at the eye height of the base mode, rolled and pitched by
## DrunkFeel.sway at `strength` (0.5: drunk 45, 1.0: drunk 90 and above, the base mode's "too much")
## at the moment of its widest roll, with the shipped PlayerTuning. Upright posts and a level rail
## show the tilt; a white dot marks the claimed facing (the head's look), the view's centre when
## sober. Dev only: nothing here reaches the game.

const MODE := "res://content/modes/base_mode.tres"
const TUNING := preload("res://client/player/player_tuning.tres")
## The sway's clock is searched over this many seconds, in SAMPLE_S steps, for its widest roll.
const SEARCH_S := 30.0
const SAMPLE_S := 0.01

## The drunk feel's strength shown, 0..1.
@export var strength := 1.0


func _ready() -> void:
	var rules := (load(MODE) as GameMode).player_rules
	_add_floor()
	_add_light()
	for i: int in range(-3, 4):
		_add_box(Vector3(i * 1.2, 1.0, -4.0), Vector3(0.12, 2.0, 0.12), Color(0.85, 0.82, 0.75))
	_add_box(Vector3(0.0, 1.2, -4.05), Vector3(8.0, 0.06, 0.06), Color(0.85, 0.3, 0.25))
	# The claimed facing: straight ahead of the unswayed head.
	_add_box(Vector3(0.0, rules.eye_height_m, -3.9), Vector3(0.05, 0.05, 0.05), Color.WHITE)
	var head := Node3D.new()
	add_child(head)
	head.position = Vector3(0.0, rules.eye_height_m, 0.0)
	var camera := Camera3D.new()
	head.add_child(camera)
	var sway := _widest_sway()
	camera.rotation = Vector3(sway.y, 0.0, sway.x)
	camera.make_current()


## The sway at the clock of its widest roll within SEARCH_S, for peer 2 (a joiner).
func _widest_sway() -> Vector2:
	var widest := Vector2.ZERO
	var clock := 0.0
	while clock < SEARCH_S:
		var sway := DrunkFeel.sway(strength, clock, 2, TUNING)
		if absf(sway.x) > absf(widest.x):
			widest = sway
		clock += SAMPLE_S
	return widest


func _add_box(center: Vector3, size: Vector3, colour: Color) -> void:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	mesh.material = material
	box.mesh = mesh
	box.position = center
	add_child(box)


func _add_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
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
