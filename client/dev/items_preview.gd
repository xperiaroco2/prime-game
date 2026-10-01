extends Node3D
## A preview of M4-8's views for `tools\run.cmd shot` (the M4 ADR's §6): items on the ground (a
## knife, a package, a kind with no look of its own), two other players carrying (a package in
## front with both hands and a knife on the belt; a knife in the hand), three circles (one done),
## and the destination marker of the own package's circle, seen through a wall. With
## `first_person`, the own player's view with the package in both hands. Fed by a fake ClientModel;
## dev only, nothing here reaches the game.

const Preview := preload("res://client/dev/screen_preview.gd")
const PLAYER := preload("res://client/player/player.tscn")
const TICK_USEC := 50000

@export var first_person := false

var _now := 1000000


func _ready() -> void:
	var mode := load(Preview.MODE) as GameMode
	var model := Preview.fake_model(mode, true)
	Preview.fold_round(model, false)
	_build_room()
	var avatars := AvatarViews.new()
	avatars.model = model
	avatars.buffer = SnapshotBuffer.new()
	avatars.rules = mode.player_rules
	avatars.clock = func() -> int: return _now
	add_child(avatars)
	var others := {
		2: {"position": Vector3(-2.0, 0, -4.0), "facing": Vector3(0.6, 0, 1)},
		3: {"position": Vector3(2.5, 0, -5.0), "facing": Vector3(-0.8, 0, 1)},
	}
	for tick: int in range(1, 6):
		_now += TICK_USEC
		var fields := {"tick": tick, "avatars": _avatars(others)}
		model.fold_snapshot(fields)
		avatars.buffer.add(tick, fields["avatars"] as Dictionary, _now)
	_now += TICK_USEC * 10
	_fold_items(model)
	var circles := CircleViews.new()
	circles.model = model
	circles.mode = mode
	add_child(circles)
	var items := ItemViews.new()
	items.model = model
	items.mode = mode
	items.avatars = avatars
	add_child(items)
	var camera := Camera3D.new()
	if first_person:
		var player := PLAYER.instantiate() as PlayerController
		player.rules = mode.player_rules
		player.reads_device_input = false
		player.position = Vector3(0, 0, 3)
		add_child(player)
		player.set_physics_process(false)
		items.player = player
		player.look(0.25, -0.15)
		camera = player.get_camera()
	else:
		camera.transform = Transform3D(Basis.from_euler(Vector3(-0.5, 0, 0)), Vector3(0, 5.5, 5))
		add_child(camera)
	camera.current = true


func _avatars(others: Dictionary) -> Dictionary:
	var made := {}
	for peer: int in others:
		var other: Dictionary = others[peer]
		made[peer] = {
			"position": other["position"],
			"velocity": Vector3.ZERO,
			"facing": other["facing"],
			"downed": false,
			"invulnerable": false,
			"held_item": -1,
			"belt_item": -1,
		}
	return made


func _fold_items(model: ClientModel) -> void:
	var circles := {
		1: [Color(0.9, 0.25, 0.25), Vector3(-3.5, 0, -1.0)],
		2: [Color(0.25, 0.45, 0.95), Vector3(1.5, 0, -12.0)],
		3: [Color(0.3, 0.8, 0.35), Vector3(4.0, 0, 0.5)],
	}
	for station: int in circles:
		var circle: Array = circles[station]
		model.fold(
			&"StationPlaced",
			{"station": station, "kind": &"circle", "colour": circle[0], "position": circle[1]}
		)
	var spawns := [
		[11, &"knife", Vector3(-0.8, 0, 0.5), 1],
		[12, &"wrench", Vector3(0.8, 0, 0.8), -1],
		[13, &"package", Vector3(0.0, 0, -1.5), 1],
		[14, &"package", Vector3.ZERO, 3],
		[15, &"knife", Vector3.ZERO, -1],
		[16, &"knife", Vector3.ZERO, -1],
		[17, &"package", Vector3.ZERO, 2],
		[18, &"package", Vector3(4.0, 0, 0.5), 3],
	]
	for spawn: Array in spawns:
		var fields := {"item": spawn[0], "kind": spawn[1], "position": spawn[2]}
		if spawn[3] as int >= 0:
			fields["station"] = spawn[3]
			fields["colour"] = (circles[spawn[3]] as Array)[0]
		model.fold(&"ItemSpawned", fields)
	model.fold(&"ItemPickedUp", {"peer": 2, "item": 15})
	model.fold(&"ItemPickedUp", {"peer": 2, "item": 14, "belted": 15})
	model.fold(&"ItemPickedUp", {"peer": 3, "item": 16})
	model.fold(&"ItemPickedUp", {"peer": model.own_peer, "item": 17})
	model.fold(&"PackageDelivered", {"item": 18, "station": 3})


## A floor, a wall in front of the blue circle, light and a sky.
func _build_room() -> void:
	_box(Vector3(0, -0.05, -4), Vector3(16, 0.1, 22), Color(0.45, 0.45, 0.47))
	_box(Vector3(1.5, 1.5, -9.5), Vector3(6, 3, 0.3), Color(0.6, 0.58, 0.55))
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.65, 0.75)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(environment)


func _box(at: Vector3, size: Vector3, colour: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	mesh.material = material
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.position = at
	add_child(view)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	add_child(body)
