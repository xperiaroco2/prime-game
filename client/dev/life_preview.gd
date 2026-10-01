extends Node3D
## A preview of the life looks for `tools\run.cmd shot` (the M4 ADR's §6 and D8): from the left, a
## living player, a downed one lying on its side in its colour, a body (grey with a dark cross) and
## an invulnerable player in its white shell, on a floor; the life panel of a downed player being
## raised over them. Dev only: nothing here reaches the game.

const MODE := "res://content/modes/base_mode.tres"
const BODY := preload("res://client/player/remote_player_body.tscn")


func _ready() -> void:
	var mode := load(MODE) as GameMode
	var rules := mode.player_rules
	_add_floor()
	_add_light()
	var standing := _add_player(rules, Vector3(-3.0, 0.0, 0.0))
	standing.set_downed(false)
	var downed := _add_player(rules, Vector3(-1.0, 0.0, 0.0))
	downed.set_living(false)
	downed.set_downed(true)
	var body := LifeLooks.body(rules)
	body.position = Vector3(1.0, 0.0, 0.0)
	body.rotation = Vector3(0.0, PI * 0.5, 0.0)
	add_child(body)
	var shielded := _add_player(rules, Vector3(3.0, 0.0, 0.0))
	shielded.set_invulnerable(true)
	shielded.set_process(false)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.6, 5.5)
	camera.rotation = Vector3(deg_to_rad(-22.0), 0.0, 0.0)
	add_child(camera)
	camera.make_current()
	var ui := GameUi.new()
	add_child(ui)
	ui.show_screen(GameFlow.Screen.ROUND)
	ui.life.show_hud(_downed_hud(mode))


## A downed player 4 s into its knockdown, raised by Player1 for a second of three.
static func _downed_hud(mode: GameMode) -> LifeHud.Shown:
	var model := ClientModel.new(mode)
	model.own_peer = 2
	for peer: int in [1, 2]:
		var member := ClientModel.Member.new()
		member.name = "Player%d" % peer
		model.roster[peer] = member
	var countdowns := LifeCountdowns.new(mode.player_rules, LifeCountdowns.raise_seconds_of(mode))
	var knocked := {"peer": 2, "position": Vector3.ZERO}
	model.fold(&"KnockedDown", knocked)
	countdowns.on_event(&"KnockedDown", knocked, 2, 0.0)
	var raise := {"raiser": 1, "target": 2}
	model.fold(&"RaiseStarted", raise)
	countdowns.on_event(&"RaiseStarted", raise, 2, 80.0)
	return LifeHud.of(model, countdowns, 100.0, LifeHud.Local.new())


func _add_player(rules: PlayerRules, at: Vector3) -> RemotePlayerBody:
	var player := BODY.instantiate() as RemotePlayerBody
	player.rules = rules
	player.position = at
	add_child(player)
	# A quarter turn, so the lying capsule and the visor show their length.
	player.rotation = Vector3(0.0, PI * 0.5, 0.0)
	return player


func _add_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 10.0)
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
