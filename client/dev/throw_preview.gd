extends Node3D
## A preview of thrown items in flight (#645, 37e; ARCHITECTURE §4.7.25) for `tools\run.cmd shot`:
## the base mode with a Throw rule of the preview's own, built in code (10 m/s, 9.8 m/s², radius
## 0.15 m, 3 s: a preview's numbers, not content; the base mode gets its rule in 37f). Player 2
## has thrown five packages one after another along the same arc, drawn at the avatars' tick (a
## strobe of one arc: each item an ordinary ItemView, no trail); player 3 threw a package at the
## wall, which stopped it, and it falls straight down to its rest; the own player's predicted
## knife, thrown at a wall a step ahead, is held at that wall. Fed by a fake ClientModel on a
## fake clock; dev only, nothing here reaches the game.

const Preview := preload("res://client/dev/screen_preview.gd")
const PLAYER := preload("res://client/player/player.tscn")
const TICK_USEC := 50000
const GRAVITY := Vector3(0, -9.8, 0)
const STROBE: Array[int] = [21, 22, 23, 24, 25]
const STROBE_TICKS: Array[int] = [3, 6, 9, 12, 15]
const FALLING := 31
const OWN_KNIFE := 41

var _now := 1000000


func _ready() -> void:
	var mode := (load(Preview.MODE) as GameMode).duplicate(true) as GameMode
	mode.actions.append(_throw_rule())
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
		2: {"position": Vector3(-4.0, 0, -2.0), "facing": Vector3(1, 0, -0.3)},
		3: {"position": Vector3(1.5, 0, -6.0), "facing": Vector3(0, 0, -1)},
	}
	for tick: int in range(1, 6):
		_now += TICK_USEC
		var fields := {"tick": tick, "avatars": _avatars(others)}
		model.fold_snapshot(fields)
		avatars.buffer.add(tick, fields["avatars"] as Dictionary, _now)
	_now += TICK_USEC * 10
	var items := ItemViews.new()
	items.model = model
	items.mode = mode
	items.avatars = avatars
	add_child(items)
	# The tick the avatars are drawn at, as ItemViews will read it in its physics step.
	var drawn := floorf(avatars.buffer.render_tick(_now))
	for i: int in STROBE.size():
		var velocity := Vector3(0.8, 0.55, -0.15).normalized() * 10.0
		_throw(
			model, items, STROBE[i], 2, Vector3(-4.0, 1.6, -2.0), velocity, drawn - STROBE_TICKS[i]
		)
	_throw(
		model,
		items,
		FALLING,
		3,
		Vector3(1.5, 1.6, -6.0),
		Vector3(0, 0.2, -1).normalized() * 10.0,
		drawn - 14
	)
	# The wall stopped it 0.15 m before its face (z -9.35); the rest is straight below the stop.
	_event(
		model,
		items,
		&"ItemPlaced",
		{"item": FALLING, "position": Vector3(1.5, 0, -9.2), "cause": Items.THROWN}
	)
	var player := PLAYER.instantiate() as PlayerController
	player.rules = mode.player_rules
	player.reads_device_input = false
	player.position = Vector3(4.5, 0, 1.0)
	add_child(player)
	player.set_physics_process(false)
	items.player = player
	_event(
		model,
		items,
		&"ItemSpawned",
		{"item": OWN_KNIFE, "kind": &"knife", "position": Vector3.ZERO}
	)
	_event(model, items, &"ItemPickedUp", {"peer": model.own_peer, "item": OWN_KNIFE})
	items.predict_throw(1, player.get_camera().global_position, player.look_vector())
	var camera := Camera3D.new()
	camera.transform = Transform3D(Basis.from_euler(Vector3(-0.45, 0, 0)), Vector3(0, 5.0, 6.5))
	add_child(camera)
	camera.current = true


## A Throw rule of the preview's own: HoldsItem, OverFloor, then ThrowItem.
func _throw_rule() -> Rule:
	var thrown_by := ThrowItem.new()
	thrown_by.speed_mps = 10.0
	thrown_by.gravity_mps2 = 9.8
	thrown_by.radius_m = 0.15
	thrown_by.longest_flight_s = 3.0
	var rule := Rule.new()
	rule.trigger = Intents.THROW
	rule.conditions = [HoldsItem.new(), OverFloor.new()]
	rule.effects = [thrown_by]
	return rule


## Peer `peer` threw a new item `id` from `origin` at `velocity` at host tick `tick`.
func _throw(
	model: ClientModel,
	items: ItemViews,
	id: int,
	peer: int,
	origin: Vector3,
	velocity: Vector3,
	tick: float
) -> void:
	var kind := &"package"
	var spawned := {"item": id, "kind": kind, "position": Vector3.ZERO}
	if kind == &"package":
		spawned["station"] = 1
		spawned["colour"] = Color(0.9, 0.55, 0.2) if peer == 2 else Color(0.3, 0.75, 0.35)
	_event(model, items, &"ItemSpawned", spawned)
	_event(model, items, &"ItemPickedUp", {"peer": peer, "item": id})
	var launch := {
		"item": id,
		"peer": peer,
		"origin": origin,
		"velocity": velocity,
		"gravity": GRAVITY,
		"tick": int(tick),
	}
	_event(model, items, &"ItemThrown", launch)


func _event(
	model: ClientModel, items: ItemViews, event_name: StringName, fields: Dictionary
) -> void:
	model.fold(event_name, fields)
	items.on_event(event_name, fields)


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


## A floor, the back wall the knife hit, the wall a step in front of the own player, light.
func _build_room() -> void:
	_box(Vector3(0, -0.05, -4), Vector3(16, 0.1, 22), Color(0.45, 0.45, 0.47))
	_box(Vector3(1.5, 1.5, -9.5), Vector3(6, 3, 0.3), Color(0.6, 0.58, 0.55))
	_box(Vector3(4.5, 1.5, -0.3), Vector3(1.6, 3, 0.2), Color(0.55, 0.6, 0.62))
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
