class_name MainMenu
extends Control
## The main menu (ARCHITECTURE §4.7; the M6 design §3 item 1): "Join with a code" (a field and
## Join), Host (a room with a code), "Direct (LAN or VPN)" (the host's address and port, Join, and
## Host Direct over ENet, as before M6), Quit, and why the last session ended. The fields keep what
## was typed when a join fails. Built in code; the game connects its signals.

signal code_join_requested(code: String)
signal code_host_requested
signal host_requested(port: int)
signal join_requested(address: String, port: int)
signal quit_requested

const DEFAULT_ADDRESS := "127.0.0.1"

var code_edit := LineEdit.new()
var address_edit := LineEdit.new()
var port_box := SpinBox.new()
var reason_label := Label.new()


func _init() -> void:
	name = "MainMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := UiParts.centered_column(self, "PrimeGame")
	column.add_child(UiParts.heading("Join with a code"))
	code_edit.placeholder_text = "the code the host gave you"
	code_edit.custom_minimum_size = Vector2(467, 0)
	code_edit.text_submitted.connect(func(_text: String) -> void: _join_code())
	var code_row := UiParts.labelled("Code", code_edit)
	code_row.add_child(UiParts.button("Join", _join_code))
	column.add_child(code_row)
	column.add_child(UiParts.button("Host", func() -> void: code_host_requested.emit()))
	column.add_child(UiParts.heading("Direct (LAN or VPN)"))
	address_edit.text = DEFAULT_ADDRESS
	address_edit.placeholder_text = "the host's address or name"
	address_edit.custom_minimum_size = Vector2(467, 0)
	column.add_child(UiParts.labelled("Address", address_edit))
	port_box.min_value = 1
	port_box.max_value = 65535
	port_box.value = LaunchOptions.DEFAULT_PORT
	column.add_child(UiParts.labelled("Port", port_box))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(
		UiParts.button(
			"Join", func() -> void: join_requested.emit(address_edit.text.strip_edges(), port())
		)
	)
	buttons.add_child(UiParts.button("Host Direct", func() -> void: host_requested.emit(port())))
	column.add_child(buttons)
	column.add_child(UiParts.button("Quit", func() -> void: quit_requested.emit()))
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.custom_minimum_size = Vector2(700, 0)
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(reason_label)


func port() -> int:
	return int(port_box.value)


## Why the last session ended, in words; empty hides it.
func set_reason(text: String) -> void:
	reason_label.text = text
	reason_label.visible = not text.is_empty()


func _join_code() -> void:
	code_join_requested.emit(code_edit.text)
