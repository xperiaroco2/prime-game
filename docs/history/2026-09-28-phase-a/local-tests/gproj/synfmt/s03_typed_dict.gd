extends RefCounted

var scores: Dictionary[String, int] = {}
var by_id: Dictionary[int, Array] = {}


func add(name: String, pts: int) -> void:
	scores[name] = scores.get(name, 0) + pts
