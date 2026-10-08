class_name ControlsPanel
extends VBoxContainer
## Settings › Controls (#211): a row per rebindable action (Controls.ACTIONS) with its name, a
## button with the bound key's label (KeyLabel) and "Same key" when another action of one of its
## phases has that key; Reset to defaults below. The Esc menu's Controls tab shows it today; the Toy
## Esc menu (#491) hosts this panel in its Settings page and gives it the Toy look.
##
## A click on a key button (or ui_accept on it) starts a capture: the button reads "Press a key…"
## and the next key press or mouse button press binds, applied to the InputMap and saved at once
## (Controls.apply(), write()): so a panel on in-memory Controls (a test, a preview) changes the
## global InputMap too, and a test restores it with `Controls.new().apply()`. A release (that of the
## click that started it) and an echo do nothing; Esc cancels (#488's rule 2: Esc is fixed); a
## click on another key or on Reset cancels and reaches that button; a click on the capturing key
## binds the left mouse button. The capture runs in _input and consumes every other event but the
## wheel (it scrolls the page and never binds), so neither the menu (Esc), the focus (the arrows,
## ui_accept) nor the game sees one; it is cancelled when the panel hides. Built in code, styled
## only through the shared theme (#150).

## Emitted after a binding or a reset changed the controls.
signal changed

## The deck's English texts (prime-game-ui copy/strings.csv at ui-0.2.0) of its deck keys.
const WORDS: Dictionary[StringName, String] = {
	&"settings.controls.press_key": "Press a key…",
	&"settings.controls.reset": "Reset to defaults",
	&"settings.controls.same_key": "Same key",
}
## The row name's and the key button's room (layout, on the 1920x1080 base): the longest English
## name, "Swap hand and belt", fits.
const NAME_WIDTH := 330.0
const KEY_WIDTH := 200.0

## The controls this panel changes; in memory until the game gives it the player's.
var controls := Controls.new()
## The key button of each action.
var key_buttons: Dictionary[StringName, Button] = {}
## The "Same key" mark of each action.
var clash_labels: Dictionary[StringName, Label] = {}
var reset_button: Button
## The action a capture binds; &"" while none runs.
var capturing: StringName = &""


func _init() -> void:
	name = "Controls"
	theme_type_variation = &"EscPage"
	for action: StringName in Controls.ACTIONS:
		var key := Button.new()
		key.name = String(action)
		key.custom_minimum_size = Vector2(KEY_WIDTH, 0)
		key.pressed.connect(start_capture.bind(action))
		key_buttons[action] = key
		var clash := UiParts.styled_label(word(&"settings.controls.same_key"), &"Shortfalls")
		clash_labels[action] = clash
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = Controls.name_of(action)
		label.custom_minimum_size = Vector2(NAME_WIDTH, 0)
		row.add_child(label)
		row.add_child(key)
		row.add_child(clash)
		add_child(row)
	reset_button = UiParts.button(word(&"settings.controls.reset"), reset)
	reset_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(reset_button)
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
		key.text = word(&"settings.controls.press_key") if on else _label(action)
		clash_labels[action].visible = not controls.clashes_of(action).is_empty()


## A deck key's text in the current language, or its English text while no translation has it.
static func word(deck_key: StringName) -> String:
	var text := String(TranslationServer.translate(deck_key))
	if text == String(deck_key) or text.is_empty():
		return WORDS.get(deck_key, String(deck_key))
	return text


func _input(event: InputEvent) -> void:
	if not is_capturing():
		return
	if not is_visible_in_tree():
		cancel_capture()
		return
	if capture(event):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and is_capturing():
		cancel_capture()


func _bind(event: InputEvent) -> void:
	var action := capturing
	capturing = &""
	if controls.bind(action, event):
		_save()
	else:
		refresh()


func _save() -> void:
	controls.apply()
	controls.write()
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
