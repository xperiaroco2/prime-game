class_name UiSounds
extends RefCounted
## The UI's sounds (#525, #657; ARCHITECTURE §4.7.40), on the UI bus (AudioBuses.UI), each from one
## AudioStreamPlayer of its own under the window's root that is made at its first play and kept.
## - The click: ToyPress plays it as a Toy button goes down (`button_down`: a mouse or touch press,
##   or `ui_accept` on the focused button), never on hover, release or a toggle's change alone; a
##   disabled button sends no `button_down`. SfxSet's UI_CLICK. Kept under the root: a press that
##   swaps or frees its screen (Host, Join, Back, Leave) frees the button, not the click.
## - The outro: EndScreen plays it once each time End starts (`outro_began`), the one sound of both
##   outcomes (#657). SfxSet's UI_OUTRO; no voice is routed through it (#213).
## A node outside the tree, or a set whose files do not load, plays nothing.

## The click's player's name under the root.
const PLAYER := &"UiSounds"
## The outro's player's name under the root.
const OUTRO_PLAYER := &"UiOutro"
## How many clicks overlap at most (fast presses).
const POLYPHONY := 4

## How many clicks played (tests).
static var clicks := 0
## How many outros played (tests).
static var outros := 0


## Plays the click for a press of `button`.
static func click(button: Node) -> void:
	if _play(button, PLAYER, SfxSet.UI_CLICK, POLYPHONY):
		clicks += 1


## Plays the outro of End for `screen` (one per End: EndScreen emits `outro_began` once).
static func outro(screen: Node) -> void:
	if _play(screen, OUTRO_PLAYER, SfxSet.UI_OUTRO, 1):
		outros += 1


## The click's player under the root of `tree`, or null before the first click.
static func player_in(tree: SceneTree) -> AudioStreamPlayer:
	return tree.root.get_node_or_null(NodePath(String(PLAYER))) as AudioStreamPlayer


## The outro's player under the root of `tree`, or null before the first outro.
static func outro_player_in(tree: SceneTree) -> AudioStreamPlayer:
	return tree.root.get_node_or_null(NodePath(String(OUTRO_PLAYER))) as AudioStreamPlayer


## Plays sound `id` from the player `player_name` under the root of `node`'s tree, made at its
## first play; false when `node` is outside the tree or the id has no stream.
static func _play(node: Node, player_name: StringName, id: StringName, polyphony: int) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var root := node.get_tree().root
	var player := root.get_node_or_null(NodePath(String(player_name))) as AudioStreamPlayer
	if player == null:
		var stream := SfxSet.new().stream_for(id)
		if stream == null:
			return false
		player = AudioStreamPlayer.new()
		player.name = player_name
		player.stream = stream
		player.bus = AudioBuses.UI
		player.max_polyphony = polyphony
		root.add_child(player)
	player.play()
	return true
