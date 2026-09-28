extends SceneTree
## Proposal sketch: load a scene, wait N frames, save a PNG, quit.

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = args[0]
	var out_path: String = args[1]
	var packed: PackedScene = load(scene_path) as PackedScene
	root.add_child(packed.instantiate())
	for i: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var err: Error = img.save_png(out_path)
	print("saved=%s err=%d size=%s" % [out_path, err, img.get_size()])
	quit(0 if err == OK else 1)
