class_name KeyLabel
extends RefCounted
## The name of a bound key as the player reads it on a keycap (#211; #488's rule 7, the HUD, the
## downed screen and Settings › Controls all show keys through it): from the action's current
## binding in the InputMap, so a prompt such as "Hold F to give up" follows a rebind (Controls),
## and from the keyboard layout, so a physical key reads as the Latin letter printed on it
## (`DisplayServer.keyboard_get_label_from_physical`: the physical Q is "A" on AZERTY).
##
## - A key: the layout's label (`OS.get_keycode_string`: "F", "Shift", "Tab") when it is a Latin
##   letter or sign; a label in another script is the US name (the physical F reads "F", not the
##   Cyrillic "А" of a Ukrainian layout: keycaps carry both, and players name game keys by the
##   Latin one; shown()). Space is the deck's `key.space`. Headless Godot has no keyboard layout
##   (its DisplayServer prints an error and returns the key): the physical key's own name there.
## - A mouse button: the deck's `key.mouse_left` and `key.mouse_right` (LMB, RMB); the others are
##   "Mouse <n>".
## - Deck keys (#208's copy deck) are read through TranslationServer, with the deck's English text
##   when no translation holds the key yet.
## - Nothing bound: "".

## The last code point of the Latin scripts (Latin Extended-B): a layout's label above it, and
## below the special keys, is shown by its US name.
const LATIN_END := 0x024F

## Deck keys a label may come from, with the deck's English text (prime-game-ui copy/strings.csv
## at ui-0.2.0).
const WORDS: Dictionary[StringName, String] = {
	&"key.space": "Space",
	&"key.mouse_left": "LMB",
	&"key.mouse_right": "RMB",
}
const MOUSE_WORDS: Dictionary[MouseButton, StringName] = {
	MOUSE_BUTTON_LEFT: &"key.mouse_left",
	MOUSE_BUTTON_RIGHT: &"key.mouse_right",
}


## The label of `action`'s first bound event; "" when the action is missing or unbound.
static func of_action(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event: InputEvent in InputMap.action_get_events(action):
		var text := of_event(event)
		if not text.is_empty():
			return text
	return ""


## The label of one bound event (a key or a mouse button); "" for any other event.
static func of_event(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		return of_key(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)
	var button := event as InputEventMouseButton
	if button != null:
		if MOUSE_WORDS.has(button.button_index):
			return word(MOUSE_WORDS[button.button_index])
		return "Mouse %d" % button.button_index
	return ""


## The label of the physical key `physical` on this keyboard layout.
static func of_key(physical: Key) -> String:
	if physical == KEY_NONE:
		return ""
	var label := physical
	if DisplayServer.get_name() != "headless":
		label = shown(physical, DisplayServer.keyboard_get_label_from_physical(physical))
	if label == KEY_SPACE:
		return word(&"key.space")
	return OS.get_keycode_string(label)


## The key to name for the physical key `physical` whose layout label is `label`: the label when it
## is a special key (Shift, Tab) or a Latin letter or sign, else `physical` (its US name).
static func shown(physical: Key, label: Key) -> Key:
	if label == KEY_NONE:
		return physical
	if (label & KEY_SPECIAL) != 0 or label <= LATIN_END:
		return label
	return physical


## A deck key's text in the current language, or its English text while no translation has it.
static func word(deck_key: StringName) -> String:
	var text := String(TranslationServer.translate(deck_key))
	if text == String(deck_key) or text.is_empty():
		return WORDS.get(deck_key, String(deck_key))
	return text
