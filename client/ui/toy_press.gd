class_name ToyPress
extends Node
## The press motion of a Toy button (#289; prime-game-ui spec §6). The face's offset transform,
## which is visual only (layout, the hit area and a container's sort never touch it), moves to a
## target read from the face's theme constants:
## `press_disabled` while disabled; else `press_held` while held (from `button_down` to
## `button_up`, so for mouse, touch and `ui_accept`) or while a toggle face is on; else
## `press_hover` while the pointer is over it; else 0. It re-evaluates on the face's `draw`,
## `button_down`, `button_up`, `mouse_entered`, `mouse_exited` and `toggled`, and tweens only when
## the target changes: TRANS_SINE, EASE_OUT over `press_duration_ms` (70), or
## `press_duration_reduced_ms` (0: at once) under UiPrefs.reduced_motion. The base of its
## ToyRaised is hidden while the face is disabled ("unplugged"). A face disabled while held drops
## the hold: Godot sends no `button_up` then, and drops the release on a disabled button.
##
## A toggle that stays on (the Esc menu's Ready, a selected preset card) rests at `press_held`,
## sunk onto its base with its pressed look (#289's decision; the flat tabs and chips hold 0).
## A press (`button_down`) also plays the UI's click (UiSounds, #525); hover plays nothing.
## The handlers are public so the tests call them (a headless run has no pointer).

## The button that moves.
var face: BaseButton
## Its ToyRaised wrapper, whose base it hides while the face is disabled; null for a flat button.
var raised: ToyRaised
## How many tweens it started: a test reads that a refresh with the same target starts none.
var tweens_started := 0
## The running motion; null after a move at once.
var tween: Tween

var _held := false
var _hovered := false
var _target := 0


## Attaches the motion to `button` (inside `wrapper`, if raised) as an internal child.
static func attach(button: BaseButton, wrapper: ToyRaised = null) -> ToyPress:
	var press := ToyPress.new()
	press.name = "ToyPress"
	press.face = button
	press.raised = wrapper
	button.offset_transform_enabled = true
	button.add_child(press, false, Node.INTERNAL_MODE_FRONT)
	button.draw.connect(press.refresh)
	button.button_down.connect(press.on_button_down)
	button.button_up.connect(press.on_button_up)
	button.mouse_entered.connect(press.on_mouse_entered)
	button.mouse_exited.connect(press.on_mouse_exited)
	button.toggled.connect(press.on_toggled)
	return press


## The offset, in px down, the face moves to in its present state.
func target_offset() -> int:
	if face.disabled:
		return face.get_theme_constant(&"press_disabled")
	if _held or (face.toggle_mode and face.button_pressed):
		return face.get_theme_constant(&"press_held")
	if _hovered:
		return face.get_theme_constant(&"press_hover")
	return 0


## The motion's length now, in ms.
func duration_ms() -> int:
	if UiPrefs.reduced_motion:
		return face.get_theme_constant(&"press_duration_reduced_ms")
	return face.get_theme_constant(&"press_duration_ms")


## Re-evaluates the target and the base; moves the face only when the target changed.
func refresh() -> void:
	if face.disabled:
		_held = false
	if raised != null:
		raised.show_base(not face.disabled)
	var target := target_offset()
	if target == _target:
		return
	_target = target
	if tween != null:
		tween.kill()
		tween = null
	var ms := duration_ms()
	if ms <= 0 or not face.is_inside_tree():
		face.offset_transform_position.y = target
		return
	tweens_started += 1
	tween = face.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(face, ^"offset_transform_position:y", float(target), ms / 1000.0)


func on_button_down() -> void:
	_held = true
	refresh()
	UiSounds.click(face)


func on_button_up() -> void:
	_held = false
	refresh()


func on_mouse_entered() -> void:
	_hovered = true
	refresh()


func on_mouse_exited() -> void:
	_hovered = false
	refresh()


func on_toggled(_on: bool) -> void:
	refresh()
