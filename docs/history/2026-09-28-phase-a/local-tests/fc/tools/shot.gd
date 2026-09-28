extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	print("display=", DisplayServer.get_name(), " renderer=", RenderingServer.get_current_rendering_driver_name(), " method=", RenderingServer.get_current_rendering_method())
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var ps: PackedScene = load(args[0])
	root.add_child(ps.instantiate())
	for i: int in int(args[2]):
		await process_frame
	print("awaiting frame_post_draw")
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var err: Error = img.save_png(args[1])
	print("saved err=", err, " size=", img.get_size())
	quit(0)
