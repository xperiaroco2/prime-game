extends SceneTree
var _done: bool = false
var _frames: int = 0

func _process(_delta: float) -> bool:
	_frames += 1
	if _done:
		return false
	if not Engine.has_singleton("EditorInterface"):
		return false
	var ei: Object = Engine.get_singleton("EditorInterface")
	var fs: EditorFileSystem = ei.call("get_resource_filesystem")
	if fs == null or fs.is_scanning():
		return false
	_done = true
	print("frames=", _frames, " editor_hint=", Engine.is_editor_hint())
	var item: ItemData = ItemData.new()
	item.display_name = "Generated"
	print("save tres err=", ResourceSaver.save(item, "res://gen/generated_editor.tres"))
	var root: Node3D = Node3D.new()
	root.name = "Room"
	root.set_meta("item", load("res://content/c.tres"))
	var ps: PackedScene = PackedScene.new()
	ps.pack(root)
	print("save tscn err=", ResourceSaver.save(ps, "res://gen/room_editor.tscn"))
	var ex: PackedScene = load("res://levels/no_uid_scene.tscn")
	print("resave err=", ResourceSaver.save(ex, "res://gen/resaved_editor.tscn"))
	var st: PackedScene = load("res://levels/stale.tscn")
	print("resave stale err=", ResourceSaver.save(st, "res://gen/stale_resaved_editor.tscn"))
	var wr: PackedScene = load("res://levels/wrong.tscn")
	print("resave wrong err=", ResourceSaver.save(wr, "res://gen/wrong_resaved_editor.tscn"))
	var lg: Resource = load("res://content/legacy_header.tres")
	print("resave legacy err=", ResourceSaver.save(lg, "res://gen/legacy_resaved_editor.tres"))
	root.free()
	quit()
	return true
