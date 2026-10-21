extends SceneTree
## Runs one scene in an off-screen window for `tools\run.cmd run --offscreen <scene>` (#1141;
## docs/AGENT_WORKFLOW.md §11.5): places the window off every screen first (offscreen.gd, which
## explains why `--position` alone does not), then changes to the scene. The runner passes the
## scene in PRIME_OFFSCREEN_SCENE and the window's size in PRIME_WINDOW:
##   PRIME_OFFSCREEN_SCENE=res://x.tscn PRIME_WINDOW=1152x648 godot --position 30000,-30000
##       --resolution 1x1 -s res://tools/offscreen/offscreen_scene.gd [-- <the scene's arguments>]
## On failure prints OFFSCREEN error <why> and exits 1.

const Offscreen := preload("res://tools/offscreen/offscreen.gd")
const SCENE_ENV := "PRIME_OFFSCREEN_SCENE"


func _initialize() -> void:
	var placed: String = Offscreen.place()
	if placed != "":
		_fail(placed)
		return
	var scene: String = OS.get_environment(SCENE_ENV)
	if scene == "":
		_fail("no scene: the runner sets %s=<res://scene.tscn>" % SCENE_ENV)
		return
	var error: Error = change_scene_to_file(scene)
	if error != OK:
		_fail("cannot run %s: %s" % [scene, error_string(error)])


func _fail(why: String) -> void:
	print("OFFSCREEN error ", why)
	quit(1)
