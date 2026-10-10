class_name ControlsPanel
extends VBoxContainer
## Settings › Controls (#211; the Toy look of #491, prime-game-ui handoff s05 `settings-controls`
## at ui-0.4.0): a 64 px ToySettingRow per rebindable action (Controls.ACTIONS) with its name, the
## ToyChipAlert "Same key" when another action of one of its phases has that key, and a wide
## ToyKeyButton with the bound key's label (KeyLabel); ResetGap and Reset to defaults below. A
## SettingsPage holds it, in the Esc menu and in the main menu's Settings (each its own).
##
## A click on a key button (or ui_accept on it) starts a capture: the button reads "Press a key…"
## and the next key press or mouse button press binds, applied to the InputMap and saved at once
## (Controls.apply(), write()): so a panel on in-memory Controls (a test, a preview) changes the
## global InputMap too, and a test restores it with `Controls.new().apply()`. A release (that of the
## click that started it) and an echo do nothing; Esc cancels (#488's rule 2: Esc is fixed); a
## click on another key or on Reset cancels and reaches that button; a click on the capturing key
## binds the left mouse button. The capture runs in _input and consumes every other event but the
## wheel (it scrolls the page and never binds), so neither the menu (Esc), the focus (the arrows,
## ui_accept) nor the game sees one; it is cancelled when the panel hides. The rows read the
## controls again whenever the panel shows: the other SettingsPage may have changed them.

## Emitted after a binding or a reset changed the controls.
signal changed

## Each action's row name in the handoff.
const ROW_NAMES: Dictionary[StringName, String] = {
	&"move_forward": "Forward",
	&"move_back": "Backward",
	&"move_left": "Left",
	&"move_right": "Right",
	&"sprint": "Sprint",
	&"jump": "Jump",
	&"interact": "Interact",
	&"use": "Use",
	&"put_down": "PutDown",
	&"swap": "Swap",
	&"map": "Map",
	&"give_up": "GiveUp",
	&"ready": "ReadyKey",
	&"voice_talk": "Talk",
	&"spectate_next": "SpectateNext",
	&"spectate_previous": "SpectatePrevious",
}
## The spacer above Reset, the handoff's ResetGap (0, 12). Its note says "4 + 12 + 4 = 20 px", but
## it builds the column as ToyColumnEight, so the gap is 8 + 12 + 8 = 28 px; the node data wins.
const RESET_GAP := Vector2(0, 12)

## The controls this panel changes; in memory until the game gives it the player's.
var controls := Controls.new()
## The name of each action's row.
var name_labels: Dictionary[StringName, Label] = {}
## The key button of each action.
var key_buttons: Dictionary[StringName, Button] = {}
## The "Same key" chip of each action, and its text.
var clash_chips: Dictionary[StringName, PanelContainer] = {}
var clash_labels: Dictionary[StringName, Label] = {}
## Reset to defaults (ToyButtonGhostOnLight).
var reset_button := Button.new()
## The action a capture binds; &"" while none runs.
var capturing: StringName = &""


func _init() -> void:
	name = "Controls"
	theme_type_variation = &"ToyColumnEight"
	for action: StringName in Controls.ACTIONS:
		var key := Button.new()
		key.name = "Bind"
		key.theme_type_variation = &"ToyKeyButton"
		key.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		key.pressed.connect(start_capture.bind(action))
		UiParts.sized(key, true)
		key_buttons[action] = key
		var chip := PanelContainer.new()
		chip.name = "Same"
		chip.theme_type_variation = &"ToyChipAlert"
		var clash := UiParts.styled_label("", &"ToyChipAlertText")
		clash.name = "Text"
		clash.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		chip.add_child(clash)
		clash_chips[action] = chip
		clash_labels[action] = clash
		var row := SettingRows.row(str(ROW_NAMES.get(action, action)), "", chip)
		var label := SettingRows.name_of(row)
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		name_labels[action] = label
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.get_node(^"H").add_child(key)
		add_child(row)
	var gap := Control.new()
	gap.name = "ResetGap"
	gap.custom_minimum_size = RESET_GAP
	add_child(gap)
	reset_button.name = "Reset"
	reset_button.theme_type_variation = &"ToyButtonGhostOnLight"
	reset_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	reset_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset_button.pressed.connect(reset)
	ToyPress.attach(reset_button)
	add_child(reset_button)
	retext()


## Writes every word in the current language (the copy deck's translation, #208): the row names,
## "Same key", Reset and the key labels. Built before Game applies the player's language, the panel
## writes them again on NOTIFICATION_TRANSLATION_CHANGED (§4.7.26).
func retext() -> void:
	for action: StringName in name_labels:
		name_labels[action].text = Controls.name_of(action)
		clash_labels[action].text = KeyLabel.word(&"settings.controls.same_key")
	reset_button.text = KeyLabel.word(&"settings.controls.reset")
	refresh()


## Shows `with` (the player's controls, Game's) and changes it from now on.
func setup(with: Controls) -> void:
	controls = with
	cancel_capture()
	refresh()


## Starts a capture for `action`: the next key or mouse button binds it.
func start_capture(action: StringName) -> void:
	if not key_buttons.has(action):
		return
	capturing = action
	refresh()


## Ends a capture with nothing bound.
func cancel_capture() -> void:
	capturing = &""
	refresh()


## Whether a capture runs.
func is_capturing() -> bool:
	return capturing != &""


## A capture's handling of `event`: Esc cancels, a key or mouse button press binds; a click on
## another of the panel's buttons cancels and reaches that button, the wheel passes on (the page
## scrolls) and the capture waits; anything else waits. Returns whether the event is the capture's
## (the caller consumes it then).
func capture(event: InputEvent) -> bool:
	if not is_capturing():
		return false
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return true
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_ESCAPE:
			cancel_capture()
			return true
		_bind(event)
	elif event is InputEventMouseButton:
		return _capture_click(event as InputEventMouseButton)
	return true


## Every action back to its default, applied and saved.
func reset() -> void:
	cancel_capture()
	controls.reset()
	_save()


## Draws the bindings: each key's label, the capturing row's prompt and the same-key marks.
func refresh() -> void:
	for action: StringName in key_buttons:
		var key := key_buttons[action]
		var on := action == capturing
		key.toggle_mode = on
		key.set_pressed_no_signal(on)
		key.text = KeyLabel.word(&"settings.controls.press_key") if on else _label(action)
		clash_chips[action].visible = not controls.clashes_of(action).is_empty()


func _input(event: InputEvent) -> void:
	if not is_capturing():
		return
	if not is_visible_in_tree():
		cancel_capture()
		return
	if capture(event):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		retext()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree() and is_capturing():
			cancel_capture()
		elif is_visible_in_tree():
			# The other SettingsPage (the main menu's, the Esc menu's) may have rebound a key.
			refresh()


func _bind(event: InputEvent) -> void:
	var action := capturing
	capturing = &""
	if controls.bind(action, event):
		_save()
	else:
		refresh()


func _save() -> void:
	controls.apply()
	var saved := controls.write()
	if saved != OK:
		push_warning("controls: %s not saved: %s" % [controls.path, error_string(saved)])
	refresh()
	changed.emit()


## capture() of a mouse button: the wheel passes on, a press on another button cancels and passes
## on, any other press binds.
func _capture_click(button: InputEventMouseButton) -> bool:
	if Controls.normalised(button) == null:
		return false
	if not button.pressed:
		return true
	if _other_button_at(button.position) != null:
		cancel_capture()
		return false
	_bind(button)
	return true


## The panel's button under `at` (viewport coordinates) other than the capturing key; null if none.
func _other_button_at(at: Vector2) -> Button:
	var buttons: Array[Button] = [reset_button]
	buttons.append_array(key_buttons.values())
	for button: Button in buttons:
		if button == key_buttons.get(capturing) or not button.is_visible_in_tree():
			continue
		if button.get_global_rect().has_point(at):
			return button
	return null


func _label(action: StringName) -> String:
	var event := controls.event_of(action)
	return KeyLabel.of_event(event) if event != null else ""
