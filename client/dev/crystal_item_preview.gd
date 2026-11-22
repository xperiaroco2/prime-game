extends Node3D
## The energy crystal as an item for `tools\run.cmd shot` (#1672): what everyone but its carrier
## sees. Left, Player2 carries a charged crystal; right, Player3 carries a spent one (Idle with the
## carry layer, the crystal on the carry point as ItemViews puts it); in front, a charged and a
## spent crystal lie on the floor (after the zap at the ship's exit, a throw, a downed carrier).
## Without the LFS art the bodies stay capsules and the crystals the labelled boxes. Dev only:
## nothing here reaches the game.

const MODE := "res://content/modes/base_mode.tres"
const BODY := preload("res://client/player/remote_player_body.tscn")


func _ready() -> void:
	var rules := (load(MODE) as GameMode).player_rules
	var character := CharacterSet.load_default()
	_add_floor()
	_add_light()
	var kinds: Array[StringName] = [&"crystal_charged", &"crystal_spent"]
	for i: int in kinds.size():
		var side := -0.55 if i == 0 else 0.55
		var carrying := _add_player(rules, character, Vector3(side, 0.0, 0.0), side * -40.0, i + 1)
		carrying.carry_point().add_child(ItemView.make(i + 1, kinds[i], Color.WHITE))
		var plan := AvatarClips.Plan.new()
		plan.base = AvatarClips.IDLE
		plan.carry = true
		carrying.apply_plan(plan)
		var lying := ItemView.make(i + 3, kinds[i], Color.WHITE)
		add_child(lying)
		lying.position = Vector3(side * 0.7, 0.0, 0.9)
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(-14.0), 0.0, 0.0)), Vector3(0.0, 1.35, 2.9)
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
