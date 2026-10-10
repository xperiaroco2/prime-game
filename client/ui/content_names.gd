class_name ContentNames
extends RefCounted
## Content names in the player's language (#549, #208 part c; ARCHITECTURE §4.7.48): what a screen
## shows for a role, an item kind, a task type, a room or a map is the UI copy deck's key for it
## (§4.7.26), else the content's own display name (as the content writes it), else its id. A
## Control whose text is that string shows it translated and retranslates it on a language switch;
## text() gives it in the language now, for a string built around it. Pure: no node.
##
## The deck (ui-0.4.0) names the base mode's two roles, three item kinds and two task types, and
## the greybox's six rooms (`room.<id>`). It has no key for a map ("House", from the scene's file
## name) or the House's rooms (their ids show): no key is invented here, the gaps go to the UI
## track (#549's PR lists them).

## The copy deck's key of each role, by role id (the base mode's crew are the deck's Engineers).
const ROLES: Dictionary[StringName, String] = {
	&"crew": "role.engineer",
	&"dissident": "role.dissident",
}
## The copy deck's key of each item kind, by kind id.
const ITEMS: Dictionary[StringName, String] = {
	&"package": "item.package",
	&"knife": "item.knife",
	&"switch": "item.switch",
}
## The copy deck's key of each task type, by type id.
const TASKS: Dictionary[StringName, String] = {
	&"delivery": "task.delivery",
	&"switches": "task.switches",
}
## A room's key is this and its id, where the deck has one.
const ROOM_PREFIX := "room."


## A role's deck key, else the mode's display name for it, else its id.
static func role(id: StringName, mode: GameMode) -> String:
	if ROLES.has(id):
		return ROLES[id]
	var found := mode.find_role(id) if mode != null else null
	return _named(found.display_name if found != null else "", id)


## An item kind's deck key, else the mode's display name for it, else its id.
static func item(id: StringName, mode: GameMode) -> String:
	if ITEMS.has(id):
		return ITEMS[id]
	var found := mode.find_item_kind(id) if mode != null else null
	return _named(found.display_name if found != null else "", id)


## A task type's deck key, else the mode's display name for it, else its id.
static func task(id: StringName, mode: GameMode) -> String:
	if TASKS.has(id):
		return TASKS[id]
	var found := mode.find_task_type(id) if mode != null else null
	return _named(found.display_name if found != null else "", id)


## A room's deck key (`room.<id>`) where the deck has one, else its id.
static func room(id: StringName) -> String:
	var key := ROOM_PREFIX + String(id)
	return key if has_key(key) else String(id)


## A map's name: its scene's file name ("House"); the deck has no map names yet.
static func map(path: String) -> String:
	return path.get_file().get_basename().capitalize()


## A name above in the language now: a key's text, any other name as it is.
static func text(name: String) -> String:
	return String(TranslationServer.translate(name))


## Whether the loaded deck has `key` (a key's text is never the key itself).
static func has_key(key: String) -> bool:
	return String(TranslationServer.translate(key)) != key


static func _named(display_name: String, id: StringName) -> String:
	return display_name if not display_name.is_empty() else String(id)
