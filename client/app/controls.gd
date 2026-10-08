class_name Controls
extends RefCounted
## The controls the player rebinds (#211; #488's rule 5 and 6): the 16 actions of Settings ›
## Controls, one key or mouse button each, saved per player in a ConfigFile under user://
## (controls.cfg, its own file: the UserSettings file is the voice's and the language's), read at
## the start and applied to the InputMap, so every `Input.is_action_*` and every KeyLabel follows.
##
## - The defaults are `project.godot`'s input map (ProjectSettings `input/<action>`, never the
##   InputMap, which apply() changes). The file holds only the actions bound away from their
##   default, so a default changed later (give_up from G to F, #211) reaches every player who never
##   rebound it; reset() empties it.
## - A binding is a physical key (the project's input map binds physical keys: the same place on
##   any layout) or a mouse button but the wheel, with no modifiers, for every device. Esc is fixed
##   (#488's rule 2): it cancels a capture and is never bound; nor are F3 and Enter (FIXED).
## - "Same key" is per phase (#488's rule 6): two actions on one key clash only when both act in
##   one phase of PHASES. give_up (downed) and ready (lobby) share F by default and never clash.
## - A missing, damaged or foreign entry (an unknown action, an unreadable binding) keeps the
##   default.
## - Never sent to anyone.

## Where an action acts: the lobby screen (the lobby and the countdown) or the round by the own
## life. Bit flags, so an action may act in several.
enum Phase { LOBBY = 1, ALIVE = 2, DOWNED = 4, DEAD = 8 }

const FILE := "user://controls.cfg"
const SECTION := "bindings"
## InputMap's device id for any device (its C++ ALL_DEVICES), as project.godot's events carry.
const ALL_DEVICES := -1
## The actions with a key that is not rebindable and that no binding may take: the debug overlay
## (F3) and fullscreen (Alt+Enter, so Enter).
const FIXED: Array[StringName] = [&"debug_overlay", &"toggle_fullscreen"]
## The mouse "buttons" that never bind: none, and the wheel's four.
const NOT_BINDABLE_BUTTONS: Array[MouseButton] = [
	MOUSE_BUTTON_NONE,
	MOUSE_BUTTON_WHEEL_UP,
	MOUSE_BUTTON_WHEEL_DOWN,
	MOUSE_BUTTON_WHEEL_LEFT,
	MOUSE_BUTTON_WHEEL_RIGHT,
]
## The rebindable actions in Settings › Controls' order, with the deck key (#208) of each row's name
## (#488's table).
const ACTIONS: Dictionary[StringName, StringName] = {
	&"move_forward": &"control.forward",
	&"move_back": &"control.backward",
	&"move_left": &"control.left",
	&"move_right": &"control.right",
	&"sprint": &"control.sprint",
	&"jump": &"control.jump",
	&"interact": &"control.interact",
	&"use": &"control.use",
	&"put_down": &"control.put_down",
	&"swap": &"control.swap",
	&"task_screen": &"control.map",
	&"give_up": &"control.give_up",
	&"ready": &"control.ready",
	&"voice_talk": &"control.talk",
	&"spectate_next": &"control.spectate_next",
	&"spectate_previous": &"control.spectate_previous",
}
## Where each action acts, as the client reads it today: the lobby screen reads movement, talk and
## Ready (Game._unhandled_input); the round reads the item keys and the raise while living
## (ItemInteractions, LifeView), the crawl while downed (no sprint, no jump: PlayerController), the
## give-up while downed and the spectate buttons while dead (LifeView), and the map on any life
## (GameUi). Talk sends while the own life is living, in the lobby too, whose VoiceRule hears
## (VoiceSender.may_speak).
const PHASES: Dictionary[StringName, int] = {
	&"move_forward": Phase.LOBBY | Phase.ALIVE | Phase.DOWNED,
	&"move_back": Phase.LOBBY | Phase.ALIVE | Phase.DOWNED,
	&"move_left": Phase.LOBBY | Phase.ALIVE | Phase.DOWNED,
	&"move_right": Phase.LOBBY | Phase.ALIVE | Phase.DOWNED,
	&"sprint": Phase.LOBBY | Phase.ALIVE,
	&"jump": Phase.LOBBY | Phase.ALIVE,
	&"interact": Phase.ALIVE,
	&"use": Phase.ALIVE,
	&"put_down": Phase.ALIVE,
	&"swap": Phase.ALIVE,
	&"task_screen": Phase.ALIVE | Phase.DOWNED | Phase.DEAD,
	&"give_up": Phase.DOWNED,
	&"ready": Phase.LOBBY,
	&"voice_talk": Phase.LOBBY | Phase.ALIVE,
	&"spectate_next": Phase.DEAD,
	&"spectate_previous": Phase.DEAD,
}

## The file, under user://; "" keeps the bindings in memory only (read() and write() touch no file).
var path := ""

## The actions bound away from their default: action -> its event.
var _bound: Dictionary[StringName, InputEvent] = {}


func _init(at := "") -> void:
	path = at


## The player's file (FILE), read if it exists. One file for every window of one PC: the controls
## are the person's, not the window's (UserSettings' per-window files keep each window's
## microphone). Each window keeps its own copy in memory, so with two windows open the last one
## to save wins (a dev playtest's second window can undo the first one's rebind).
static func for_this_player() -> Controls:
	var controls := Controls.new(FILE)
	controls.read()
	return controls


## The deck key of `action`'s row name; &"" for an action that is not rebindable.
static func deck_key(action: StringName) -> StringName:
	return ACTIONS.get(action, &"")


## `action`'s row name in the current language (the copy deck's translation, #208).
static func name_of(action: StringName) -> String:
	var key := deck_key(action)
	if key == &"":
		return String(action)
	return String(TranslationServer.translate(key))


## `action`'s default from `project.godot`; null when it has none.
static func default_event(action: StringName) -> InputEvent:
	var setting: Variant = ProjectSettings.get_setting("input/%s" % action)
	if not setting is Dictionary:
		return null
	var events: Variant = (setting as Dictionary).get("events", [])
	if not events is Array:
		return null
	for each: Variant in events as Array:
		var event := normalised(each as InputEvent)
		if event != null:
			return event
	return null


## `event` as a binding: a physical key or a mouse button with nothing else (no modifiers, not
## pressed), for every device as in project.godot; null for anything else, Esc, a fixed key
## (is_fixed_key()), a key with no code, or the wheel (it only clicks: a held action could never
## be held on it).
static func normalised(event: InputEvent) -> InputEvent:
	var key := event as InputEventKey
	if key != null:
		var physical := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if physical == KEY_NONE or physical == KEY_ESCAPE or is_fixed_key(physical):
			return null
		var bound := InputEventKey.new()
		bound.physical_keycode = physical
		bound.device = ALL_DEVICES
		return bound
	var button := event as InputEventMouseButton
	if button != null and button.button_index not in NOT_BINDABLE_BUTTONS:
		var bound := InputEventMouseButton.new()
		bound.button_index = button.button_index
		bound.device = ALL_DEVICES
		return bound
	return null


## Whether `physical` is the key of a fixed action (FIXED, whatever its modifiers): bound to an
## action as well, both would act on it (Ready on F3 would never toggle: Game takes F3 first).
static func is_fixed_key(physical: Key) -> bool:
	for action: StringName in FIXED:
		var setting: Variant = ProjectSettings.get_setting("input/%s" % action)
		if not setting is Dictionary:
			continue
		var events: Variant = (setting as Dictionary).get("events", [])
		if not events is Array:
			continue
		for each: Variant in events as Array:
			var key := each as InputEventKey
			if key != null and (key.physical_keycode == physical or key.keycode == physical):
				return true
	return false


## Whether two bindings are the same key or button.
static func same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (
			(a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
		)
	return false


## A binding as the file writes it: "key:<physical keycode>" or "mouse:<button index>".
static func encode(event: InputEvent) -> String:
	if event is InputEventKey:
		return "key:%d" % (event as InputEventKey).physical_keycode
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	return ""


## A binding read back from encode()'s text; null for anything unreadable.
static func decode(text: String) -> InputEvent:
	var parts := text.strip_edges().split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	var number := parts[1].to_int()
	if number <= 0:
		return null
	match parts[0]:
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = number as Key
			return normalised(key)
		"mouse":
			var button := InputEventMouseButton.new()
			button.button_index = number as MouseButton
			return normalised(button)
	return null


## The binding `action` has now: the player's, else the default.
func event_of(action: StringName) -> InputEvent:
	if _bound.has(action):
		return _bound[action]
	return default_event(action)


## Whether `action` has its default binding.
func is_default(action: StringName) -> bool:
	return not _bound.has(action)


## Binds `action` to `event` (normalised()); false, and nothing changes, for an action that is not
## rebindable or an event that cannot be a binding. The default itself clears the player's entry.
func bind(action: StringName, event: InputEvent) -> bool:
	var bound := normalised(event)
	if not ACTIONS.has(action) or bound == null:
		return false
	var fallback := default_event(action)
	if fallback != null and same(bound, fallback):
		_bound.erase(action)
	else:
		_bound[action] = bound
	return true


## Every action back to its default.
func reset() -> void:
	_bound.clear()


## The other actions bound to `action`'s key that act in a phase it acts in, in ACTIONS' order.
func clashes_of(action: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	var mine := event_of(action)
	if mine == null:
		return found
	for other: StringName in ACTIONS:
		if other == action or (PHASES.get(other, 0) & PHASES.get(action, 0)) == 0:
			continue
		var theirs := event_of(other)
		if theirs != null and same(mine, theirs):
			found.append(other)
	return found


## Every rebindable action's binding into the InputMap (each action's events replaced by its one
## binding), so the game's input and every KeyLabel follow.
func apply() -> void:
	for action: StringName in ACTIONS:
		var event := event_of(action)
		if event == null or not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event)


## Reads the file; a missing file, and any entry that is unknown or unreadable, keeps the defaults.
func read() -> Error:
	_bound.clear()
	if path.is_empty():
		return ERR_FILE_NOT_FOUND
	var file := ConfigFile.new()
	var code := file.load(path)
	if code != OK:
		return code
	if not file.has_section(SECTION):
		return OK
	for key: String in file.get_section_keys(SECTION):
		var action := StringName(key)
		var event := decode(str(file.get_value(SECTION, key, "")))
		if event != null:
			bind(action, event)
	return OK


## Writes the bindings away from their default (none: an empty file).
func write() -> Error:
	if path.is_empty():
		return OK
	var file := ConfigFile.new()
	for action: StringName in ACTIONS:
		if _bound.has(action):
			file.set_value(SECTION, String(action), encode(_bound[action]))
	return file.save(path)
