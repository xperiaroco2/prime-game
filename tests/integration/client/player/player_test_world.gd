extends Node3D
## A small physics world for the player controller's suites: a 60 m floor at y = 0, the level
## pieces a test adds, local players, downed ones and remote capsules, and waits over physics steps.
## A suite adds one in `before_test()` and frees it in `after_test()`. Forward is -Z.

const PLAYER_SCENE := preload("res://client/player/player.tscn")
const REMOTE_SCENE := preload("res://client/player/remote_player_body.tscn")

## The fixture mode's movement numbers (FixtureModes.player_rules), the client's PlayerRules.
var rules := FixtureModes.player_rules()


func _ready() -> void:
	add_box(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))


func add_player(at: Vector3) -> PlayerController:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.reads_device_input = false
	player.rules = rules
	player.position = at
	add_child(player)
	return player


func add_downed(at: Vector3) -> PlayerController:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.reads_device_input = false
	player.rules = rules
	player.life = ClientModel.Life.DOWNED
	player.position = at
	add_child(player)
	return player


func add_remote(at: Vector3) -> RemotePlayerBody:
	var body := REMOTE_SCENE.instantiate() as RemotePlayerBody
	body.rules = rules
	body.position = at
	add_child(body)
	return body


func add_box(center: Vector3, size: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	add_static(box, Transform3D(Basis.IDENTITY, center))


## `steps` stairs rising toward -Z from z = -1, each riser step height and each tread 0.3 m,
## narrower than the capsule, so it rests on a stair's edge below the stair's top. The last one is
## long.
func add_stairs(steps: int) -> void:
	for i: int in steps:
		var tread := 0.3 if i < steps - 1 else 3.0
		var height := rules.step_height_m * (i + 1)
		var near_z := -1.0 - 0.3 * i
		add_box(Vector3(0.0, height * 0.5, near_z - tread * 0.5), Vector3(4.0, height, tread))


## A 10 m ramp rising toward -Z at `angle` (radians), leaving the floor at z = `foot_z`.
func add_ramp(angle: float, foot_z: float) -> void:
	var length := 10.0
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 1.0, length)
	var tilt := Basis(Vector3.RIGHT, angle)
	var up_slope := Vector3(0.0, sin(angle), -cos(angle))
	var surface_middle := Vector3(0.0, 0.0, foot_z) + up_slope * length * 0.5
	add_static(box, Transform3D(tilt, surface_middle - tilt.y * 0.5))


## A pipe of `radius` lying on the floor across the way, along X, centred at z = `z`.
func add_pipe(radius: float, z: float) -> void:
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 4.0
	add_static(cylinder, Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.0, radius, z)))


func add_static(shape: Shape3D, at: Transform3D) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.transform = at
	add_child(body)


func stand_in(player: PlayerController) -> PredictedStamina:
	return player.stamina as PredictedStamina


func frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


## Horizontal metres per second over `count` physics steps, after `settle` steps to reach
## full speed.
func measure_speed(player: PlayerController, settle: int = 10, count: int = 60) -> float:
	await frames(settle)
	var from := player.global_position
	await frames(count)
	var to := player.global_position
	return horizontal_distance(from, to) * Engine.physics_ticks_per_second / count


func peak_height(player: PlayerController, count: int) -> float:
	var peak := player.global_position.y
	for i: int in count:
		await frames(1)
		peak = maxf(peak, player.global_position.y)
	return peak


func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
