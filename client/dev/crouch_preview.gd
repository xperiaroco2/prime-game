extends Node3D
## A preview of other players drawn crouched for `tools\run.cmd shot` (#792; the crouch ADR's KE7):
## three remote bodies on a test floor, the base mode's numbers. Left, Player2 stands; middle,
## Player3 is drawn crouched (set_crouched at once, as a body first drawn crouched): the lower
## capsule and greybox look, its head and hand lowered with them; right, Player4 crouched with the
## package in both hands (the carry point lowered too). Dev only: nothing here reaches the game.

const MODE := "res://content/modes/base_mode.tres"
const BODY := preload("res://client/player/remote_player_body.tscn")


func _ready() -> void:
	var rules := (load(MODE) as GameMode).player_rules
	_add_floor()
	_add_light()
	var standing := _add_player(rules, Vector3(-1.4, 0.0, 0.0), 0)
	standing.hand_point().add_child(ItemView.make(1, &"knife", Color.WHITE))
	var crouched := _add_player(rules, Vector3(0.0, 0.0, 0.0), 1)
	crouched.set_crouched(true, INF)
	crouched.hand_point().add_child(ItemView.make(2, &"knife", Color.WHITE))
	var carrying := _add_player(rules, Vector3(1.4, 0.0, 0.0), 2)
	carrying.set_crouched(true, INF)
	carrying.carry_point().add_child(ItemView.make(3, &"package", Color(0.8, 0.6, 0.3)))
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(-8.0), 0.0, 0.0)), Vector3(0.0, 1.5, 4.2)
	)
	camera.make_current()


## A remote body of `colour` at `at`, facing the camera.
func _add_player(rules: PlayerRules, at: Vector3, colour: int) -> RemotePlayerBody:
	var player := BODY.instantiate() as RemotePlayerBody
	player.rules = rules
	add_child(player)
	player.set_colour(BodyColours.of(colour))
	player.position = at
	player.rotation = Vector3(0.0, PI + deg_to_rad(25.0), 0.0)
	return player


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
