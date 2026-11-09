extends Node3D
## Previews of the dead's hall for `tools\run.cmd shot` (#1489): the hall as a dead player sees it
## (a see-through dead player in it, by its own Environment), a print half way (the drone over the
## marker, the avatar grown to half from the feet) and the body lying where its owner died. Dev
## only: nothing here reaches the game.

enum View { HALL, PRINT, BODY }

const MODE := "res://content/modes/base_mode.tres"
const HALL_PIECE := "res://levels/lobby/dead_hall.tscn"
const HALF := 0.5
## Peer of the body shown (its colour and its name mean nothing here).
const PEER := 3

@export var view := View.HALL


func _ready() -> void:
	var rules := (load(MODE) as GameMode).player_rules
	match view:
		View.HALL:
			_show_hall(rules)
		View.PRINT:
			_show_print(rules)
		View.BODY:
			_show_body(rules)


func _show_hall(rules: PlayerRules) -> void:
	add_child((load(HALL_PIECE) as PackedScene).instantiate())
	var other := _body(rules, Vector3(2.0, 0.0, 6.0))
	AvatarViews._apply_see_through(other, AvatarViews.SEE_THROUGH)
	var camera := _camera(Vector3(0.0, 1.6, 12.0), Vector3(deg_to_rad(-4.0), 0.0, 0.0))
	camera.environment = HallVisibility.HALL_ENVIRONMENT


func _show_print(rules: PlayerRules) -> void:
	_add_ground()
	var at := Vector3(0.0, 0.0, -3.0)
	_body(rules, at).set_print_height(HALF)
	add_child(PrintViews._make_drone(at))
	_camera(Vector3(0.0, 1.8, 1.0), Vector3(deg_to_rad(-6.0), 0.0, 0.0))


func _show_body(rules: PlayerRules) -> void:
	_add_ground()
	var model := ClientModel.new(load(MODE) as GameMode)
	model.bodies[PEER] = Vector3(0.0, 0.0, -3.0)
	var views := BodyViews.new()
	views.setup(model, rules, null)
	add_child(views)
	views.sync()
	_camera(Vector3(0.0, 1.8, 1.0), Vector3(deg_to_rad(-22.0), 0.0, 0.0))


func _body(rules: PlayerRules, at: Vector3) -> RemotePlayerBody:
	var body := AvatarViews.BODY.instantiate() as RemotePlayerBody
	body.rules = rules
	add_child(body)
	body.global_position = at
	return body


func _camera(at: Vector3, rotated: Vector3) -> Camera3D:
	var camera := Camera3D.new()
	camera.position = at
	camera.rotation = rotated
	add_child(camera)
	camera.make_current()
	return camera


func _add_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.34, 0.3)
	plane.material = material
	ground.mesh = plane
	add_child(ground)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	add_child(floor_body)
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
