class_name ConnectingScreen
extends Control
## Joined or hosting, no Welcome yet (ARCHITECTURE §4.7): "Connecting to <address>", Cancel.

signal cancel_requested

var label := Label.new()


func _init() -> void:
	name = "ConnectingScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := UiParts.centered_column(self, "Connecting")
	column.add_child(label)
	column.add_child(UiParts.button("Cancel", func() -> void: cancel_requested.emit()))


func set_address(address: String) -> void:
	label.text = "Connecting to %s" % address
