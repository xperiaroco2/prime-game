extends RefCounted
## Keeps a runner's window off every screen (#1141; docs/AGENT_WORKFLOW.md §11.4). A window script
## (`shot`, `playcheck`, `run --offscreen`) calls `place()` first thing in its _initialize.
##
## Godot 4.7.2 on Windows ignores `--position -30000,-30000` for a new window:
## DisplayServerWindows::_create_window takes the primary screen when the requested rect is on no
## screen and clamps a windowed window's position into that screen's usable area, up to its far edge
## minus a third of the window's size, so the window opened at the screen's top-left corner at full
## size. Only a runtime DisplayServer.window_set_position moves a window without that clamp. So the
## runner (tools/runner/offscreen.py, which explains the start) opens the window at 1x1 px asked
## far right and up (`--position 30000,-30000 --resolution 1x1`): its client area opens just past
## the screen's top-right corner. It passes the size it wants in the PRIME_WINDOW environment
## variable; place() moves the window to POSITION, then grows it, and prints one line the runner
## checks before it accepts the run:
##   OFFSCREEN window <x>,<y> <w>x<h> screens <x>,<y>,<w>,<h>[;...] ticks <ms since start>
## (the window's rect with its title bar and borders, every screen's rect). Returns "" when placed,
## else why not (the caller fails with it).
## Once off-screen, place() sets WINDOW_FLAG_NO_FOCUS (#1505): the window never activates again, so
## it cannot take the foreground from a game the human plays. Its first show, in Main::setup2
## before any script runs, may still activate it: the runner gives the foreground back
## (tools/runner/focus.py). The flag also makes the window topmost, harmless at POSITION.
##   const Offscreen := preload("res://tools/offscreen/offscreen.gd")
##   var placed: String = Offscreen.place()
##   if placed != "": _fail(placed); return

const POSITION := Vector2i(-30000, -30000)
const ENV := "PRIME_WINDOW"
const LINE := "OFFSCREEN window "


## The window size the runner asked for (PRIME_WINDOW=<w>x<h>), or ZERO.
static func wanted() -> Vector2i:
	var parts: PackedStringArray = OS.get_environment(ENV).split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


## Moves the main window off-screen, gives it PRIME_WINDOW's size and makes it unfocusable; ""
## when it is off every screen and has that size.
static func place() -> String:
	if DisplayServer.get_name() == "headless":
		return "running headless; this script needs a real window (off-screen)"
	var want: Vector2i = wanted()
	if want.x <= 0 or want.y <= 0:
		return "no window size: the runner sets %s=<w>x<h> (tools/runner/offscreen.py)" % ENV
	DisplayServer.window_set_position(POSITION)
	DisplayServer.window_set_size(want)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	return report(want)


## Prints the OFFSCREEN line for the window as it is now; "" when it is off every screen and, with
## want, has that size.
static func report(want: Vector2i = Vector2i.ZERO) -> String:
	var rect := Rect2i(
		DisplayServer.window_get_position_with_decorations(),
		DisplayServer.window_get_size_with_decorations()
	)
	var screens := PackedStringArray()
	var on := PackedStringArray()
	for i: int in DisplayServer.get_screen_count():
		var screen := Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
		screens.append(
			"%d,%d,%d,%d" % [screen.position.x, screen.position.y, screen.size.x, screen.size.y]
		)
		if screen.intersects(rect):
			on.append(str(i))
	print(
		(
			"%s%d,%d %dx%d screens %s ticks %d"
			% [
				LINE,
				rect.position.x,
				rect.position.y,
				rect.size.x,
				rect.size.y,
				";".join(screens),
				Time.get_ticks_msec()
			]
		)
	)
	if not on.is_empty():
		return "the window %s is on screen %s, not off-screen" % [rect, ",".join(on)]
	var inner: Vector2i = DisplayServer.window_get_size()
	if want != Vector2i.ZERO and inner != want:
		return "the window is %s, not the %s asked for" % [inner, want]
	return ""
