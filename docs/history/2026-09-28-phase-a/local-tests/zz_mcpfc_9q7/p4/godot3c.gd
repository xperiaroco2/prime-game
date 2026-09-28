extends Node

func _on_body(_b: Node) -> void:
	pass

func _ready() -> void:
	connect("tree_exiting", self, "_on_body")
	var t: int = OS.get_ticks_msec()
	rset("x", 1)
