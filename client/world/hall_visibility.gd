class_name HallVisibility
extends RefCounted
## Which side of a map this client draws (#1489): a level holds the dead's hall as a piece in the
## group `dead_hall`, far from the rest. A client whose own player is not waiting there hides the
## hall, and one that is hides the rest of the level's top-level nodes (the map is not its world,
## though it keeps colliding, far away) and lights the hall with its own environment, which the
## piece does not carry. A level without the piece stays as it is.

const GROUP := &"dead_hall"
const HALL_ENVIRONMENT: Environment = preload(
	"res://assets/environment/lobby/materials/lobby_env.tres"
)

var _hall: Node3D
var _in_hall := false
var _hidden: Array[Node3D] = []


## Applies what `in_hall` says, only when it or the level changed. `camera` is the one shown now
## (it changes with the view), or null.
func sync(level: Node, in_hall: bool, camera: Camera3D) -> void:
	if level == null or not level.is_inside_tree():
		_forget()
		return
	var hall := level.get_tree().get_first_node_in_group(GROUP) as Node3D
	if hall == null or not level.is_ancestor_of(hall):
		_forget()
		return
	if camera != null:
		camera.environment = HALL_ENVIRONMENT if in_hall else null
	if hall == _hall and in_hall == _in_hall:
		return
	_show_all()
	_hall = hall
	_in_hall = in_hall
	if not in_hall:
		hall.visible = false
		return
	hall.visible = true
	for child: Node in level.get_children():
		var side := child as Node3D
		if side != null and side != hall and side.visible:
			side.visible = false
			_hidden.append(side)


func _show_all() -> void:
	for side: Node3D in _hidden:
		if is_instance_valid(side):
			side.visible = true
	_hidden.clear()


## A level swap freed what the last sync hid.
func _forget() -> void:
	_show_all()
	_hall = null
	_in_hall = false
