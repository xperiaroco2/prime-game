@tool
extends Node

@export_tool_button("Rebuild", "Reload") var rebuild_btn: Callable = _rebuild
static var instances: int = 0


func _rebuild() -> void:
	pass


func classify(v: Variant) -> String:
	match v:
		var x when x is int and x > 10:
			return "big"
		_:
			return "other"


func f(n: Node) -> bool:
	var p: String = r"C:\raw\path"
	@warning_ignore_start("unused_variable")
	var a: int = 1
	@warning_ignore_restore("unused_variable")
	return n is not Node3D and p != ""
