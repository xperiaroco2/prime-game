extends Node3D
## A dev room for the first-person controller (#46), not a level: a floor, walls, a step of step
## height, a ledge above it, a doorway, and dummy players. Run it (it opens a window):
##   tools\run.cmd run client/dev/test_room.tscn
## Click to capture the mouse, Esc to release it. WASD, Shift to sprint, Space to jump.
## F1 toggles the downed mode (it crawls, never sprints or jumps, and pushes nobody),
## F2 puts the player and the dummies back where they started.
## Dummies: green stands in the doorway and can be pushed; yellow walks back and forth across the
## room and pushes whoever is in its way. Both are player controllers in this same world, so they
## see the player without a network's delay. Blue and red are remote capsules whose client never
## moves them, like a frozen client: the player pushes into them and slides round them.

const PLAYER_SCENE := preload("res://client/player/player.tscn")
## The movement numbers come from the game's mode, as in the game.
const MODE := "res://content/modes/base_mode.tres"
## Where the yellow walker turns back, in metres from the room's middle along X.
const WALK_TURN_X := 6.0

var _rules: PlayerRules = (load(MODE) as GameMode).player_rules
var _pushable: PlayerController
var _walker: PlayerController
## Where the pushable dummy and the walker start, for F2.
var _starts: Array[Transform3D] = []

@onready var _player: PlayerController = $Player
@onready var _overlay: Label = $Overlay
@onready var _spawn: Transform3D = _player.global_transform


func _ready() -> void:
	_player.rules = _rules
	# The game's theme sizes its text for the 1920x1080 base; Godot's default theme is unscaled
	# since #576.
	_overlay.theme = GameUi.THEME
	for remote: RemotePlayerBody in [$DummyBlue, $DummyRed]:
		remote.rules = _rules
	_pushable = _add_dummy(Vector3(-4.0, 0.0, -5.5), Color(0.3, 0.75, 0.35))
	_walker = _add_dummy(Vector3(-WALK_TURN_X, 0.0, 1.5), Color(0.9, 0.8, 0.2))
	# A quarter turn to the right: it walks toward +X.
	_walker.look(-PI / 2.0, 0.0)
	_walker.move_input = Vector2(0.0, 1.0)
	_starts = [_pushable.global_transform, _walker.global_transform]


func _physics_process(_delta: float) -> void:
	var heading := -_walker.global_basis.z
	var x := _walker.global_position.x
	if (heading.x > 0.0 and x > WALK_TURN_X) or (heading.x < 0.0 and x < -WALK_TURN_X):
		_walker.look(PI, 0.0)
	var state := "sprinting" if _player.is_sprinting() else "walking"
	if _player.is_downed():
		state = "downed " + state
	_overlay.text = (
		"stamina %.0f  |  %s  |  %s\n" % [_player.stamina.get_stamina(), state, _position_text()]
		+ "F1 downed  F2 respawn  click: capture mouse  Esc: release\n"
		+ "green: push it out of the doorway  yellow: walks into you  blue, red: frozen clients"
	)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_F1:
		var downed := ClientModel.Life.DOWNED
		_player.life = ClientModel.Life.ALIVE if _player.is_downed() else downed
	elif key.physical_keycode == KEY_F2:
		_player.teleport(_spawn)
		_pushable.teleport(_starts[0])
		_walker.teleport(_starts[1])


## A player controller that reads no input, with its own camera off and a coloured capsule to see.
func _add_dummy(at: Vector3, color: Color) -> PlayerController:
	var dummy := PLAYER_SCENE.instantiate() as PlayerController
	dummy.reads_device_input = false
	dummy.rules = _rules
	(dummy.get_node("Head/Camera3D") as Camera3D).current = false
	var mesh := CapsuleMesh.new()
	mesh.radius = _rules.capsule_radius_m
	mesh.height = _rules.capsule_height_m
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.position = Vector3(0.0, _rules.capsule_height_m * 0.5, 0.0)
	dummy.add_child(body)
	dummy.position = at
	add_child(dummy)
	return dummy


func _position_text() -> String:
	var at := _player.global_position
	return "x %.2f  y %.2f  z %.2f" % [at.x, at.y, at.z]
