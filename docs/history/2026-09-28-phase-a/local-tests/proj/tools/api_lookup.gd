extends SceneTree
## Proposal sketch: print exact signatures for a class/member from the running engine's ClassDB.

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var cls: String = args[0]
	var member: String = args[1] if args.size() > 1 else ""
	if not ClassDB.class_exists(cls):
		print("NO SUCH CLASS in %s: %s" % [Engine.get_version_info().string, cls])
		quit(2)
		return
	print("%s extends %s (engine %s)" % [cls, ClassDB.get_parent_class(cls), Engine.get_version_info().string])
	for m: Dictionary in ClassDB.class_get_method_list(cls, true):
		if member == "" or m.name == member:
			var ps: PackedStringArray = []
			for a: Dictionary in m.args:
				ps.append("%s: %s" % [a.name, type_string(a.type) if a.class_name == &"" else String(a.class_name)])
			print("  func %s(%s)" % [m.name, ", ".join(ps)])
	if member != "" and not ClassDB.class_has_method(cls, member, false) and not ClassDB.class_has_signal(cls, member):
		print("  NOT FOUND: %s.%s" % [cls, member])
	quit(0)
