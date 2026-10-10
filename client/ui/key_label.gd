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
## - Deck keys are the copy deck's (#208, client/i18n/strings.csv), read only through its
##   translation in the current language ("Space" in English, "Пробіл" in Ukrainian).
## - Nothing bound: "".
## - A keycap takes the wide size (is_wide) for the physical keys Space, Shift, Tab and Esc
##   (#488 rule 7), and so follows a rebind.

## The last code point of the Latin scripts (Latin Extended-B): a layout's label above it, and
## below the special keys, is shown by its US name.
const LATIN_END := 0x024F

## The keys whose keycap is wide (#488 rule 7).
const WIDE_KEYS: Array[Key] = [KEY_SPACE, KEY_SHIFT, KEY_TAB, KEY_ESCAPE]

## The mouse buttons named by a deck key.
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


## Whether a keycap for the physical key `physical` takes the wide size: Space, Shift, Tab and Esc
## (#488 rule 7, the four the issue names; Ctrl, Enter, F5 and the mouse words stay normal until
## a screen shows one, a placeholder and not a decision).
static func is_wide(physical: Key) -> bool:
	return WIDE_KEYS.has(physical)


## Whether `action`'s keycap takes the wide size now (its first bound key, as of_action reads it).
static func is_wide_action(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	for event: InputEvent in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			return is_wide(
				key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			)
		if event is InputEventMouseButton:
			return false
	return false


## A deck key's text in the current language (the copy deck's translation).
static func word(deck_key: StringName) -> String:
	return String(TranslationServer.translate(deck_key))
