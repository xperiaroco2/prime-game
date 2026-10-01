class_name EndScreen
extends Control
## The end screen (ARCHITECTURE §4.7, §3.2): black, "The <side's display name> won" from the
## client's own mode, and nothing else (no names, no roles); the host's Back to lobby.

signal back_requested

var winner_label := Label.new()
var back_button := UiParts.button("Back to lobby", func() -> void: back_requested.emit())


func _init() -> void:
	name = "EndScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 24)
	center.add_child(column)
	winner_label.add_theme_font_size_override(&"font_size", 40)
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(winner_label)
	column.add_child(back_button)


## `hosting`: the host alone sends ReturnToLobby.
func refresh(model: ClientModel, mode: GameMode, hosting: bool) -> void:
	winner_label.text = winner_text(model.winner, mode)
	back_button.visible = hosting


static func winner_text(winner: StringName, mode: GameMode) -> String:
	if winner.is_empty():
		return "The match is over"
	var side := mode.find_side(winner)
	return "The %s won" % (side.display_name if side != null else String(winner))
