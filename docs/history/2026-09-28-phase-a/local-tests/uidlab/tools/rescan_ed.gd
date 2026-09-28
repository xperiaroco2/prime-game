extends SceneTree
var _stage: int = 0
var _wait: int = 0
var _fs: EditorFileSystem = null

func _write(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _process(_delta: float) -> bool:
	if _stage == 0:
		if not Engine.has_singleton("EditorInterface"):
			return false
		_fs = Engine.get_singleton("EditorInterface").call("get_resource_filesystem")
		if _fs == null or _fs.is_scanning():
			return false
		# Simulate an agent writing files while the editor is running.
		var c_text: String = FileAccess.get_file_as_string("res://content/c.tres")
		_write("res://content/copied_from_c.tres", c_text.replace("\"C\"", "\"CopyOfC\""))
		_write("res://content/new_legacy.tres", "[gd_resource type=\"Resource\" script_class=\"ItemData\" load_steps=2 format=3 uid=\"uid://bt6q0f2wm0563\"]\n\n[ext_resource type=\"Script\" path=\"res://scripts/item_data.gd\" id=\"1_item\"]\n\n[resource]\nscript = ExtResource(\"1_item\")\ndisplay_name = \"NewLegacy\"\n")
		_write("res://content/new_nouid.tres", "[gd_resource type=\"Resource\" script_class=\"ItemData\" format=3]\n\n[ext_resource type=\"Script\" path=\"res://scripts/item_data.gd\" id=\"1_item\"]\n\n[resource]\nscript = ExtResource(\"1_item\")\ndisplay_name = \"NewNoUid\"\n")
		# In-place resave of an existing resource.
		var c: Resource = load("res://content/c.tres")
		c.set("weight", 7)
		print("inplace save c err=", ResourceSaver.save(c))
		_fs.scan_sources()
		_stage = 1
		return false
	if _stage == 1:
		_wait += 1
		if _fs.is_scanning() or _wait < 30:
			return false
		for p: String in ["res://content/copied_from_c.tres", "res://content/new_legacy.tres", "res://content/new_nouid.tres", "res://content/c.tres"]:
			print("== ", p, "\n", FileAccess.get_file_as_string(p))
		quit()
		return true
	return false
