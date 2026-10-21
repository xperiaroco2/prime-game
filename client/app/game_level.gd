class_name GameLevel
extends RefCounted
## Game's level swap under World, out of game.gd to keep it under lint's 1000 lines (#1249): the
## level that plays (null when none) and its kind; a new one goes first under World and to
## ItemWorld, and a dropped one leaves the tree, ItemWorld and the map's data (ARCHITECTURE §4.7,
## E19: levels swap under the one persistent root).

## The level under World; null when none plays.
var node: Node
var kind := PhaseSpec.Level.NONE
var _world: Node3D
var _items: ItemWorld
var _ui: GameUi


## At Game's _ready: where levels go, and who hears of them.
func setup(world: Node3D, items: ItemWorld, ui: GameUi) -> void:
	_world = world
	_items = items
	_ui = ui


## The level of the current phase (`wanted`): the lobby (`lobby_level`, the mode's), loaded at
## once when a lobby phase starts; a map phase drops the lobby and waits for map_loaded.
func sync(wanted: PhaseSpec.Level, lobby_level: String) -> void:
	if wanted == kind:
		return
	if wanted == PhaseSpec.Level.LOBBY:
		swap((load(lobby_level) as PackedScene).instantiate(), wanted)
	elif wanted == PhaseSpec.Level.NONE or kind == PhaseSpec.Level.LOBBY:
		clear()


## `level` of `level_kind` plays now, in place of the one before.
func swap(level: Node, level_kind: PhaseSpec.Level) -> void:
	clear()
	node = level
	node.name = "Level"
	_world.add_child(node)
	_world.move_child(node, 0)
	kind = level_kind
	_items.set_level(node)


func clear() -> void:
	if node != null:
		_world.remove_child(node)
		node.queue_free()
	node = null
	kind = PhaseSpec.Level.NONE
	_items.set_level(null)
	_ui.set_map_data(MapData.new())
