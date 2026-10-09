class_name MainMenu
extends Control
## The main menu (ARCHITECTURE §4.7; the M6 design §3 item 1): "Join with a code" (a field and
## Join), Host (a room with a code), "Direct (LAN or VPN)" (the host's address and port, Join, and
## Host Direct over ENet, as before M6), Voice, Quit, and why the last session ended. The fields
## keep what was typed when a join fails. Voice (#301) swaps the menu's rows for the Voice page: the
## same VoicePanel as the Esc menu's Voice tab, which the game feeds and listens to as it does that
## tab's, and Back (or Esc). Built in code; the game connects its signals.

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
## The menu's rows: hidden while the Voice page shows.
var main_page := VBoxContainer.new()
## The Voice page (#301): the panel in the Esc menu's page room, then Back.
var voice_page := VBoxContainer.new()
var voice := VoicePanel.new()
## The menu's Voice entry and the page's Back, raised Toy buttons (their faces press).
var voice_button := UiParts.button("Voice")
var back_button := UiParts.button("common.back")


func _init() -> void:
	name = "MainMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var page := UiParts.centered_column(self, "PrimeGame")
	main_page.theme_type_variation = page.theme_type_variation
	page.add_child(main_page)
	_build_voice_page()
	page.add_child(voice_page)
	var column := main_page
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
	(voice_button.face as Button).pressed.connect(open_voice)
	column.add_child(voice_button)
	column.add_child(UiParts.button("Quit", func() -> void: quit_requested.emit()))
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.custom_minimum_size = Vector2(700, 0)
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(reason_label)
	close_voice()


func port() -> int:
	return int(port_box.value)


## Why the last session ended, in words; empty hides it.
func set_reason(text: String) -> void:
	reason_label.text = text
	reason_label.visible = not text.is_empty()


## Shows the Voice page instead of the menu's rows.
func open_voice() -> void:
	main_page.visible = false
	voice_page.visible = true


## Back to the menu's rows.
func close_voice() -> void:
	voice_page.visible = false
	main_page.visible = true


func voice_open() -> bool:
	return voice_page.visible


func _build_voice_page() -> void:
	voice_page.theme_type_variation = main_page.theme_type_variation
	var room := ScrollContainer.new()
	room.custom_minimum_size = EscMenu.PAGE_SIZE
	room.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	voice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room.add_child(voice)
	voice_page.add_child(room)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	(back_button.face as Button).pressed.connect(close_voice)
	buttons.add_child(back_button)
	voice_page.add_child(buttons)


func _join_code() -> void:
	code_join_requested.emit(code_edit.text)
