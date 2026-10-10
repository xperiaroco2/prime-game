class_name NamePlate
extends PanelContainer
## One name plate over another player's head (#257): the player's roster name and, on a
## dissident's own client for a teammate only, the TeammateMark. Nothing else: no role, no health,
## no life state (the issue's notes; the M4 ADR's §3). The tree is the UI handoff's
## (prime-game-ui `docs/handoff/s07-hud.md`, `Plates/Plate`): `Plate` ToyNamePlate > `Row`
## ToyRowEight > `Name` ToyNamePlateText and `Mark`. The look is provisional: the Toy round HUD
## (#489) restyles it; NamePlates places it and knows nothing of its look.

var row := HBoxContainer.new()
## The player's name: data, never translated (#208: auto_translate_mode DISABLED).
var name_label := UiParts.styled_label("", &"ToyNamePlateText")
var mark := TeammateMark.new()


func _init() -> void:
	name = "Plate"
	theme_type_variation = &"ToyNamePlate"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.name = "Row"
	row.theme_type_variation = &"ToyRowEight"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.name = "Name"
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.visible = false
	row.add_child(name_label)
	row.add_child(mark)
	add_child(row)
	# A container only grows to its minimum on its own: a smaller one (the large-text theme swapped
	# back, a shorter name) shrinks the plate here.
	minimum_size_changed.connect(reset_size)


## Shows `player_name`, with the teammate mark while `teammate`; shrinks to fit a shorter name.
func show_player(player_name: String, teammate: bool) -> void:
	if name_label.text == player_name and mark.visible == teammate:
		return
	name_label.text = player_name
	mark.visible = teammate
	reset_size()


## Centres the plate on `point` (the projected point over the head, in the layer's coordinates).
func centre_on(point: Vector2) -> void:
	position = point - size * 0.5


## Whether the teammate mark shows.
func is_marked() -> bool:
	return mark.visible
