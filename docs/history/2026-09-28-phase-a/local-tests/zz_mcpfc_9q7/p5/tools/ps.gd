extends SceneTree
func _initialize() -> void:
	print("exclude_addons=", ProjectSettings.get_setting("debug/gdscript/warnings/exclude_addons", "MISSING"))
	print("directory_rules=", ProjectSettings.get_setting("debug/gdscript/warnings/directory_rules", "MISSING"))
	print("Vector3 in ClassDB=", ClassDB.class_exists("Vector3"), " @GDScript=", ClassDB.class_exists("@GDScript"))
	quit(0)
