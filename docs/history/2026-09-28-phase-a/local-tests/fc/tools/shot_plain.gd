extends SceneTree
## Usage: godot --path . -s res://tools/shot.gd -- <scene> <out.png> [frames]

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = args[0]
	var out_path: String = args[1]
	var frames: int = int(args[2]) if args.size() > 2 else 5
	var packed: PackedScene = load(scene_path) as PackedScene
	root.add_child(packed.instantiate())
	for i: int in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		printerr("SHOT: empty image (display=", DisplayServer.get_name(), ")")
		quit(2)
		return
	var err: Error = img.save_png(out_path)
	print("SHOT: saved ", out_path, " size=", img.get_size(), " err=", err, " driver=", RenderingServer.get_current_rendering_driver_name(), " method=", RenderingServer.get_current_rendering_method())
	quit(0 if err == OK else 3)
