extends SceneTree
## Renders one scene in a real window and saves a PNG. Used by `tools/run.py shot`.
##
## Run windowed and off-screen, never headless or minimized: Godot does not draw then, so
## frame_post_draw would never fire.
##   godot --position -30000,-30000 --resolution 1280x720 -s res://tools/shot/shot.gd
##       -- <res://scene.tscn> <out.png> [frames]
## Prints SHOT saved <png> <width>x<height>, or SHOT error <why>. A watchdog quits after 60 s.

const WATCHDOG_S: float = 60.0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless":
		_fail("running headless; shot needs a real window")
		return
	if args.size() < 2:
		_fail("usage: -- <res://scene.tscn> <out.png> [frames]")
		return
	create_timer(WATCHDOG_S).timeout.connect(
		_fail.bind("no frame was drawn within %d s" % WATCHDOG_S)
	)
	var frames: int = int(args[2]) if args.size() > 2 else 10
	_shoot(args[0], args[1], frames)


func _shoot(scene_path: String, png_path: String, frames: int) -> void:
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		_fail("cannot load %s" % scene_path)
		return
	var instance: Node = scene.instantiate()
	root.add_child(instance)
	for i: int in frames:
		await process_frame
	if _frame_if_needed(instance):
		for i: int in 2:
			await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_fail("the viewport gave an empty image")
		return
	var error: Error = image.save_png(png_path)
	if error != OK:
		_fail("cannot save %s: %s" % [png_path, error_string(error)])
		return
	print("SHOT saved %s %dx%d" % [png_path, image.get_width(), image.get_height()])
	quit(0)


## A level piece has no camera or light of its own: add a camera that frames all its geometry
## from above at an angle, and a sun if it has no light. Returns true when something was added.
func _frame_if_needed(instance: Node) -> bool:
	if root.get_viewport().get_camera_3d() != null:
		return false
	var bounds: AABB = AABB()
	var found: bool = false
	# GeometryInstance3D: meshes and CSG, not lights (a light's AABB is its range).
	for node: Node in instance.find_children("*", "GeometryInstance3D", true, false):
		var visual: GeometryInstance3D = node as GeometryInstance3D
		if not visual.is_visible_in_tree():
			continue
		var box: AABB = visual.global_transform * visual.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
	if not found:
		return false
	var center: Vector3 = bounds.get_center()
	var radius: float = maxf(bounds.size.length() * 0.5, 0.5)
	var camera: Camera3D = Camera3D.new()
	instance.add_child(camera)
	camera.look_at_from_position(
		center + Vector3(1.0, 0.9, 1.3).normalized() * radius * 1.7, center
	)
	camera.far = radius * 10.0 + 100.0
	camera.make_current()
	var added: String = "a camera"
	if instance.find_children("*", "Light3D", true, false).is_empty():
		var sun: DirectionalLight3D = DirectionalLight3D.new()
		instance.add_child(sun)
		sun.look_at_from_position(center, center + Vector3(-0.4, -1.0, -0.6))
		added += " and a light"
	print("SHOT framed: the scene has no camera; added ", added)
	return true


func _fail(why: String) -> void:
	print("SHOT error ", why)
	quit(1)
