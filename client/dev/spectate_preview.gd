extends Node3D
## A preview of spectating for `tools\run.cmd shot` (#168; the M4 ADR's §6): what a dead Player1
## sees while it watches Player2 from its eyes. The camera stands at Player2's eye with its look,
## Player2's own body hidden (`set_watched`) and its knife in the spectate camera's first-person
## hand, as Player2's own screen shows it; Player3 stands ahead with the package in both hands. The
## HUD says "Spectating Player2" over Player2's hand and belt, with none of Player1's own slots,
## numbers or hints; the life panel shows the respawn countdown. Dev only: nothing here reaches the
## game.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
const BODY := preload("res://client/player/remote_player_body.tscn")
## Player2's items in the fake model: a knife in its hand and another on its belt.
const TARGET_KNIFE := 21
const TARGET_BELT := 22
## The fake host tick: 25 s into the round, 5 s after Player1 died.
const NOW := 500.0
const DIED_AT := 400.0


func _ready() -> void:
	var mode := load(MODE) as GameMode
	var rules := mode.player_rules
	_add_floor()
	_add_light()
	var model := _spectator_model(mode)
	# Player2, watched from its eyes: its meshes hidden, its knife in the first-person hand.
	var target := _add_player(rules, Vector3.ZERO, 0.0)
	target.set_watched(true)
	var look := Vector3(deg_to_rad(-12.0), deg_to_rad(8.0), 0.0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_transform = Transform3D(
		Basis.from_euler(look), target.global_position + Vector3.UP * rules.eye_height_m
	)
	camera.make_current()
	var hand := FirstPersonHand.new()
	camera.add_child(hand)
	var knife: ClientModel.Item = model.items[TARGET_KNIFE]
	hand.show_item(knife.kind, knife.colour)
	# Player3 ahead, carrying the package in front with both hands.
	var other := _add_player(rules, Vector3(-0.6, 0.0, -4.5), PI)
	var package: ClientModel.Item = model.items[Preview.PACKAGE]
	var carried := ItemView.make(Preview.PACKAGE, package.kind, package.colour)
	other.carry_point().add_child(carried)
	var ui := GameUi.new()
	add_child(ui)
	ui.reads_device_input = false
	ui.show_screen(GameFlow.Screen.ROUND)
	var local := HudText.Local.new()
	local.stamina = 40.0
	local.hint = "E: pick up Knife"
	local.watching = 2
	ui.refresh_round(model, mode, floori(NOW), local)
	ui.life.show_hud(_life_hud(mode, model))


## The fake round (screen_preview's) seen by Player1, dead since DIED_AT: Player2 holds a knife and
## wears another; Player3 carries the package Player1 held.
static func _spectator_model(mode: GameMode) -> ClientModel:
	var model := Preview.fake_model(mode, true)
	Preview.fold_round(model)
	model.fold(&"Died", {"peer": 1, "position": Vector3(3, 0, 2)})
	model.fold(&"ItemPickedUp", {"peer": 3, "item": Preview.PACKAGE})
	for item_id: int in [TARGET_KNIFE, TARGET_BELT]:
		model.fold(&"ItemSpawned", {"item": item_id, "kind": &"knife", "position": Vector3.ZERO})
	model.fold(&"ItemPickedUp", {"peer": 2, "item": TARGET_BELT})
	model.fold(&"ItemPickedUp", {"peer": 2, "item": TARGET_KNIFE, "belted": TARGET_BELT})
	return model


## The life panel of Player1, dead since DIED_AT, watching Player2.
static func _life_hud(mode: GameMode, model: ClientModel) -> LifeHud.Shown:
	var countdowns := LifeCountdowns.new(mode.player_rules, LifeCountdowns.raise_seconds_of(mode))
	countdowns.on_event(&"Died", {"peer": 1, "position": Vector3.ZERO}, 1, DIED_AT)
	var local := LifeHud.Local.new()
	local.read_keys()
	local.watching = 2
	return LifeHud.of(model, countdowns, NOW, local)


func _add_player(rules: PlayerRules, at: Vector3, yaw: float) -> RemotePlayerBody:
	var player := BODY.instantiate() as RemotePlayerBody
	player.rules = rules
	add_child(player)
	player.position = at
	player.rotation = Vector3(0.0, yaw, 0.0)
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
