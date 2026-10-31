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

## A role id whose deck key is not `role.<id>`: the base mode's crew are the deck's Engineers.
## Every other role, item kind and task type is found by the convention (`role.<id>`, `item.<id>`,
## `task.<id>`) where the deck has the key, so content that adds a type the deck already names
## needs no edit here (mechanics are data).
const ROLE_EXCEPTIONS: Dictionary[StringName, String] = {
	&"crew": "role.engineer",
}
## A task type id whose deck key is not `task.<id>`: the greybox's Delivery by colours (id
## `colour_delivery`, DE15 (i) of the delivery-by-meaning ADR, #828) is the Delivery its players
## play there, the deck's `task.delivery`; the House's Delivery has that id. The Generator (id
## `generator`, #800) reads as the deck's `task.switches` ("Switches"), the one key the deck has
## for it, until the UI track adds `task.generator` (a placeholder, not a decision: the engineer
## approves it in #800's PR). The photo task (id `photo`, #784) reads as the deck's
## `room.photo_zone` ("Photo zone"), the one photo key the deck has, until the UI track adds
## `task.photo` (a placeholder, not a decision: the engineer approves it in #784's PR). Cooking (id
## `cooking`, #775) reads as the deck's `room.kitchen` ("Kitchen"), the nearest key the deck has,
## until the UI track adds `task.cooking` (a placeholder, not a decision: the engineer approves it
## in #775's PR).
const TASK_EXCEPTIONS: Dictionary[StringName, String] = {
	&"colour_delivery": "task.delivery",
	&"generator": "task.switches",
	&"photo": "room.photo_zone",
	&"cooking": "room.kitchen",
}
const ROLE_PREFIX := "role."
const ITEM_PREFIX := "item."
const TASK_PREFIX := "task."
const DESCRIPTION_SUFFIX := ".description"
## A room's key is this and its id, where the deck has one.
const ROOM_PREFIX := "room."
## A station kind's key is this and its id, where the deck has one (#801: the deck has none for the
## Generator's kinds yet, the UI track adds `station.generator` and `station.switch`).
const STATION_PREFIX := "station."


## A role's deck key, else the mode's display name for it, else its id.
static func role(id: StringName, mode: GameMode) -> String:
	if ROLE_EXCEPTIONS.has(id):
		return ROLE_EXCEPTIONS[id]
	if has_key(ROLE_PREFIX + String(id)):
		return ROLE_PREFIX + String(id)
	var found := mode.find_role(id) if mode != null else null
	return _named(found.display_name if found != null else "", id)


## An item kind's deck key, else the mode's display name for it, else its id.
static func item(id: StringName, mode: GameMode) -> String:
	if has_key(ITEM_PREFIX + String(id)):
		return ITEM_PREFIX + String(id)
	var found := mode.find_item_kind(id) if mode != null else null
	return _named(found.display_name if found != null else "", id)


## A task type's deck key, else the mode's display name for it, else its id.
static func task(id: StringName, mode: GameMode) -> String:
	if TASK_EXCEPTIONS.has(id):
		return TASK_EXCEPTIONS[id]
	if has_key(TASK_PREFIX + String(id)):
		return TASK_PREFIX + String(id)
	var found := mode.find_task_type(id) if mode != null else null
	return _named(found.display_name if found != null else "", id)


## A task type's description: its deck key `task.<id>.description` (a TASK_EXCEPTIONS id: the mapped
## key and `.description`) where the deck has one, else the mode's `TaskType.description`, else an
## empty string. A lookup only: no view shows it yet (where it would show is a UI-look question,
## #1468).
static func task_description(id: StringName, mode: GameMode) -> String:
	var base := TASK_PREFIX + String(id)
	if TASK_EXCEPTIONS.has(id):
		base = TASK_EXCEPTIONS[id]
	var key := base + DESCRIPTION_SUFFIX
	if has_key(key):
		return key
	var found := mode.find_task_type(id) if mode != null else null
	return found.description if found != null else ""


## A room's deck key (`room.<id>`) where the deck has one, else its id.
static func room(id: StringName) -> String:
	var key := ROOM_PREFIX + String(id)
	return key if has_key(key) else String(id)


## A station kind's deck key (`station.<id>`) where the deck has one, else its id (a StationKind
## has no display name; #801's gap until the UI deck has the key).
static func station(id: StringName) -> String:
	var key := STATION_PREFIX + String(id)
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
