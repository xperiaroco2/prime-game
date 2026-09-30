class_name ItemKind
extends ContentPart
## A thing a player can hold, and what using it does (ARCHITECTURE §9.3): the MVP's Package and
## Knife. Its actions apply while a player holds an item of this kind (the knife's `Use`); the
## display name is the HUD's held item; the spawn tag names the markers it is placed on (§9.6).

@export var id: StringName
@export var display_name: String
@export var spawn_tag: StringName
@export var actions: Array[Rule] = []


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("an item kind has no id")
	if spawn_tag.is_empty():
		found.append("item kind %s has no spawn_tag" % id)
	return found
