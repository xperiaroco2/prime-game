extends Node3D
## A dev room for the first-person controller (#46), not a level: a floor, walls, a step of step
## height, a ledge above it, and two dummy player capsules. Run it (it opens a window):
##   tools\run.cmd run client/dev/test_room.tscn
## Click to capture the mouse, Esc to release it. WASD, Shift to sprint, Space to jump.
## F1 toggles ghost mode (Space rises, Ctrl descends), F2 puts the player back at the spawn.

@onready var _player: PlayerController = $Player
@onready var _overlay: Label = $Overlay
@onready var _spawn: Transform3D = _player.global_transform


func _physics_process(_delta: float) -> void:
	var state := (
		"ghost" if _player.ghost else ("sprinting" if _player.is_sprinting() else "walking")
	)
	_overlay.text = (
		"stamina %.0f  |  %s  |  %s\nF1 ghost  F2 respawn  click: capture mouse  Esc: release"
		% [_player.stamina.get_stamina(), state, _position_text()]
	)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_F1:
		_player.ghost = not _player.ghost
	elif key.physical_keycode == KEY_F2:
		_player.teleport(_spawn)


func _position_text() -> String:
	var at := _player.global_position
	return "x %.2f  y %.2f  z %.2f" % [at.x, at.y, at.z]
