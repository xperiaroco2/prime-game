extends SceneTree

var frames: int = 0

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		var n: Node = null
		n.get_name()
	if frames > 5:
		quit(0)
	return false
