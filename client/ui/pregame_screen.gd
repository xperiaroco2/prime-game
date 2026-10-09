class_name PregameScreen
extends Control
## The pregame screen (ARCHITECTURE §3.6, §4.7.4, #213): a dark backdrop (EndBackdrop), "Your role"
## and the own role's display name from the client's own mode, for the silent seconds before
## the round; nothing else (no other player, no word about the microphone: the engineer,
## 2026-10-02). A greybox: the Toy role reveal is #496.

## The copy deck's "Your role" (a key: Godot translates it, §4.7.26).
const TITLE_KEY := "pregame.your_role"

var title_label := Label.new()
## The own role's display name; empty before RoleAssigned.
var role_label := Label.new()


func _init() -> void:
	name = "PregameScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UiParts.backdrop(self, &"EndBackdrop")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.theme_type_variation = &"EndColumn"
	center.add_child(column)
	for label: Label in [title_label, role_label]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	title_label.text = TITLE_KEY
	role_label.theme_type_variation = &"EndTitle"
	# No input in the pregame (#488 rule 4), as on the post game screen: the backdrop draws only.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for control: Control in find_children("*", "Control", true, false):
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE


func refresh(model: ClientModel, mode: GameMode) -> void:
	role_label.text = role_text(model, mode)


## The own role's display name from `mode`, its id when the mode lacks it, "" before RoleAssigned.
static func role_text(model: ClientModel, mode: GameMode) -> String:
	if model.role.is_empty():
		return ""
	var role := mode.find_role(model.role)
	return role.display_name if role != null else String(model.role)
