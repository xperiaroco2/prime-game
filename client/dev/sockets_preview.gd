extends Node3D
## A close-up of the character's item sockets for `tools\run.cmd shot` (#1050, ARCHITECTURE
## §4.7.53): three remote bodies wearing the shipped character, each turned three-quarters to the
## camera. Left, Player2 stands idle with the knife in the hand; middle, Player3 stands idle with
## the knife on the belt (its left hip towards the camera); right, Player4 carries the package
## (Idle with the carry layer). Without the LFS art the bodies stay capsules. Dev only: nothing here
## reaches the game.

const MODE := "res://content/modes/base_mode.tres"
const BODY := preload("res://client/player/remote_player_body.tscn")


func _ready() -> void:
	var rules := (load(MODE) as GameMode).player_rules
	var character := CharacterSet.load_default()
	_add_floor()
	_add_light()
	var holding := _add_player(rules, character, Vector3(-0.9, 0.0, 0.0), 25.0, 0)
	holding.hand_point().add_child(ItemView.make(1, &"knife", Color.WHITE))
	var belted := _add_player(rules, character, Vector3(0.0, 0.0, 0.0), -70.0, 1)
	belted.belt_point().add_child(ItemView.make(2, &"knife", Color.WHITE))
	var carrying := _add_player(rules, character, Vector3(0.9, 0.0, 0.0), -30.0, 2)
	carrying.carry_point().add_child(ItemView.make(3, &"package", Color(0.8, 0.6, 0.3)))
	var plan := AvatarClips.Plan.new()
	plan.base = AvatarClips.IDLE
	plan.carry = true
	carrying.apply_plan(plan)
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(-6.0), 0.0, 0.0)), Vector3(0.0, 1.25, 2.6)
	)
	camera.fov = 50.0
	camera.make_current()


## A remote body of `colour` wearing `character` at `at`, facing the camera turned by `turn_deg`.
func _add_player(
	rules: PlayerRules, character: CharacterSet, at: Vector3, turn_deg: float, colour: int
) -> RemotePlayerBody:
	var player := BODY.instantiate() as RemotePlayerBody
	player.rules = rules
	add_child(player)
	player.set_character(character)
	player.set_colour(BodyColours.of(colour))
	player.position = at
	player.rotation = Vector3(0.0, PI + deg_to_rad(turn_deg), 0.0)
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
