extends SceneTree
var _done: bool = false
func _process(_delta: float) -> bool:
	if _done or not Engine.has_singleton("EditorInterface"):
		return false
	var fs: EditorFileSystem = Engine.get_singleton("EditorInterface").call("get_resource_filesystem")
	if fs == null or fs.is_scanning():
		return false
	_done = true
	var path: String = "res://levels/hand_room.tscn"
	var ps: PackedScene = load(path)
	var root: Node = ps.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	var ps2: PackedScene = PackedScene.new()
	print("pack=", ps2.pack(root))
	print("save=", ResourceSaver.save(ps2, path))
	root.free()
	quit()
	return true
