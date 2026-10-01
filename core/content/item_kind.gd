class_name ItemKind
extends ContentPart
## A thing a player can hold, and what using it does (ARCHITECTURE §9.3): the MVP's Package and
## Knife. Its actions apply while a player holds an item of this kind in the hand (the knife's
## `Use`), never on the belt; the display name is the HUD's hand or belt item; the spawn tag names
## the markers it is placed on (§9.6).

@export var id: StringName
@export var display_name: String
@export var spawn_tag: StringName
## How many hands it takes, 1 or 2 (vision revision 1, Two hands): a one-handed item may go on the
## belt, a two-handed one never does, and a player holding one in the hand cannot swap (§7.1). The
## neutral default is out of bounds on purpose: the data sets it (the base mode's Package: 2,
## Knife: 1), so the mode check refuses an item kind that forgot it.
@export var hands := 0
@export var actions: Array[Rule] = []


## Whether it takes both hands (`hands` 2): it is never on the belt.
func is_two_handed() -> bool:
	return hands >= 2


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("an item kind has no id")
	if spawn_tag.is_empty():
		found.append("item kind %s has no spawn_tag" % id)
	append_found(found, [out_of_bounds("item kind %s hands" % id, hands, 1, 2)])
	return found
