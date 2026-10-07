class_name ConnectingScreen
extends Control
## Joined or hosting, no Welcome yet (ARCHITECTURE §4.7; the M6 design §3 item 3): what is being
## joined (the code or the address the player typed), the step (JoinProgress: finding the game,
## connecting, joined), Cancel. A failure returns to the main menu with its reason.

signal cancel_requested

var label := Label.new()
var step_label := Label.new()


func _init() -> void:
	name = "ConnectingScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := UiParts.centered_column(self, "Connecting")
	column.add_child(label)
	column.add_child(step_label)
	column.add_child(UiParts.button("Cancel", func() -> void: cancel_requested.emit()))


## What is joined, in words (JoinProgress.target_text); the step clears until set_step().
func set_target(text: String) -> void:
	label.text = text
	step_label.text = ""


func set_step(text: String) -> void:
	step_label.text = text
