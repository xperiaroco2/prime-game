class_name UiSounds
extends RefCounted
## The UI's click (#525; ARCHITECTURE §4.7.40): ToyPress plays it as a Toy button goes down
## (`button_down`: a mouse or touch press, or `ui_accept` on the focused button), never on hover,
## release or a toggle's change alone; a disabled button sends no `button_down`. SfxSet's
## UI_CLICK on the UI bus (AudioBuses.UI), from one AudioStreamPlayer under the window's root that
## is made at the first click and kept: a press that swaps or frees its screen (Host, Join, Back,
## Leave) frees the button, not the click. A button outside the tree, or a set whose files do not
## load, clicks nothing.

## The player's name under the root.
const PLAYER := &"UiSounds"
## How many clicks overlap at most (fast presses).
const POLYPHONY := 4

## How many clicks played (tests).
static var clicks := 0


## Plays the click for a press of `button`.
static func click(button: Node) -> void:
	if button == null or not button.is_inside_tree():
		return
	var player := player_in(button.get_tree())
	if player == null:
		var stream := SfxSet.new().stream_for(SfxSet.UI_CLICK)
		if stream == null:
			return
		player = AudioStreamPlayer.new()
		player.name = PLAYER
		player.stream = stream
		player.bus = AudioBuses.UI
		player.max_polyphony = POLYPHONY
		button.get_tree().root.add_child(player)
	player.play()
	clicks += 1


## The click's player under the root of `tree`, or null before the first click.
static func player_in(tree: SceneTree) -> AudioStreamPlayer:
	return tree.root.get_node_or_null(NodePath(String(PLAYER))) as AudioStreamPlayer
