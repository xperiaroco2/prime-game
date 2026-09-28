extends SceneTree
func _init() -> void:
	print("editor_hint=", Engine.is_editor_hint())
	var tag: String = OS.get_environment("GEN_TAG")
	var item: ItemData = ItemData.new()
	item.display_name = "Generated"
	item.weight = 3
	var err: Error = ResourceSaver.save(item, "res://gen/generated_%s.tres" % tag)
	print("save tres err=", err)
	# Build a small scene referencing c.tres and the generated item
	var root: Node3D = Node3D.new()
	root.name = "Room"
	var child: Node3D = Node3D.new()
	child.name = "Prop"
	root.add_child(child)
	child.owner = root
	root.set_meta("item", load("res://content/c.tres"))
	var ps: PackedScene = PackedScene.new()
	print("pack err=", ps.pack(root))
	print("save tscn err=", ResourceSaver.save(ps, "res://gen/room_%s.tscn" % tag))
	# Re-save an existing hand-written scene
	var ex: PackedScene = load("res://levels/no_uid_scene.tscn")
	print("resave err=", ResourceSaver.save(ex, "res://gen/resaved_%s.tscn" % tag))
	root.free()
	quit()
