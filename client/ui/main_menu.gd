class_name MainMenu
extends Control
## The main menu (ARCHITECTURE §4.7): the host's address and port, Host, Join, Quit, and why the
## last session ended. Built in code; the game connects its signals.

signal host_requested(port: int)
signal join_requested(address: String, port: int)
signal quit_requested

const DEFAULT_ADDRESS := "127.0.0.1"

var address_edit := LineEdit.new()
var port_box := SpinBox.new()
var reason_label := Label.new()


func _init() -> void:
	name = "MainMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := UiParts.centered_column(self, "PrimeGame")
	address_edit.text = DEFAULT_ADDRESS
	address_edit.placeholder_text = "the host's address"
	address_edit.custom_minimum_size = Vector2(280, 0)
	column.add_child(UiParts.labelled("Address", address_edit))
	port_box.min_value = 1
	port_box.max_value = 65535
	port_box.value = LaunchOptions.DEFAULT_PORT
	column.add_child(UiParts.labelled("Port", port_box))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(UiParts.button("Host", func() -> void: host_requested.emit(port())))
	buttons.add_child(
		UiParts.button(
			"Join", func() -> void: join_requested.emit(address_edit.text.strip_edges(), port())
		)
	)
	buttons.add_child(UiParts.button("Quit", func() -> void: quit_requested.emit()))
	column.add_child(buttons)
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.custom_minimum_size = Vector2(420, 0)
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(reason_label)


func port() -> int:
	return int(port_box.value)


## Why the last session ended, in words; empty hides it.
func set_reason(text: String) -> void:
	reason_label.text = text
	reason_label.visible = not text.is_empty()
