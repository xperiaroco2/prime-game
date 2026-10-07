class_name GameWindow
extends RefCounted
## The game's window between fullscreen and a window (#517). An exported game starts fullscreen
## (project.godot's `display/window/size/mode.template`: only an export template has the
## `template` feature, so the runner's windows, the tests and the editor's runs start windowed);
## Alt+Enter (`toggle_fullscreen`) flips it. A headless window keeps no mode (it reads minimized),
## so a test gives Game a subclass that remembers what was asked.


## The mode Alt+Enter turns `current` into: a fullscreen window back to a window, any other into the
## fullscreen the game starts in (borderless, not exclusive: ARCHITECTURE §4.7.4, "The window").
static func toggled(current: DisplayServer.WindowMode) -> DisplayServer.WindowMode:
	if (
		current == DisplayServer.WINDOW_MODE_FULLSCREEN
		or current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	):
		return DisplayServer.WINDOW_MODE_WINDOWED
	return DisplayServer.WINDOW_MODE_FULLSCREEN


func mode() -> DisplayServer.WindowMode:
	return DisplayServer.window_get_mode()


func set_mode(value: DisplayServer.WindowMode) -> void:
	DisplayServer.window_set_mode(value)


func toggle_fullscreen() -> void:
	set_mode(toggled(mode()))
