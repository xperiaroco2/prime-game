extends SceneTree

func _initialize() -> void:
	for p: Dictionary in ProjectSettings.get_property_list():
		var n: String = p["name"]
		if n.begins_with("debug/gdscript"):
			print(n, " = ", ProjectSettings.get_setting(n), "  hint_string=", p.get("hint_string", ""))
	quit(0)
