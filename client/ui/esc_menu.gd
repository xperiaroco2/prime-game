class_name EscMenu
extends Control
## Esc's menu (ARCHITECTURE §4.7): Resume, Leave and Quit. On the host, Leave and Quit end the
## session for every player, so they ask first; closing the window asks the same.

signal resume_requested
signal leave_requested
signal quit_requested

const HOST_WARNING := "You host this session: leaving ends it for every player."

var warning_label := Label.new()
var buttons := VBoxContainer.new()
var confirm_box := VBoxContainer.new()
var confirm_label := Label.new()

var _hosting := false
## The signal a confirmation emits.
var _pending := Callable()


func _init() -> void:
	name = "EscMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var column := UiParts.centered_column(self, "Menu")
	warning_label.text = HOST_WARNING
	column.add_child(warning_label)
	buttons.add_child(UiParts.button("Resume", func() -> void: resume_requested.emit()))
	buttons.add_child(UiParts.button("Leave", _ask.bind(leave_requested.emit, "Leave")))
	buttons.add_child(UiParts.button("Quit", _ask.bind(quit_requested.emit, "Quit")))
	column.add_child(buttons)
	confirm_box.add_child(confirm_label)
	var row := HBoxContainer.new()
	row.add_child(UiParts.button("Yes", _confirm))
	row.add_child(UiParts.button("No", _cancel))
	confirm_box.add_child(row)
	column.add_child(confirm_box)
	open(false)


## Shows the menu's buttons; `hosting` asks before Leave and Quit.
func open(hosting: bool) -> void:
	_hosting = hosting
	_pending = Callable()
	warning_label.visible = hosting
	buttons.visible = true
	confirm_box.visible = false


## Shows the host's confirmation to quit straight away (the window's close button).
func ask_quit() -> void:
	_hosting = true
	_ask(quit_requested.emit, "Quit")


func _ask(then: Callable, what: String) -> void:
	if not _hosting:
		then.call()
		return
	_pending = then
	confirm_label.text = "%s, and end the session for every player?" % what
	buttons.visible = false
	confirm_box.visible = true


func _cancel() -> void:
	open(_hosting)


func _confirm() -> void:
	var then := _pending
	open(_hosting)
	if then.is_valid():
		then.call()
