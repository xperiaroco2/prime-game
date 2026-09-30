class_name ReplayWorldQuery
extends WorldQuery
## Answers from a recorded command log, in order, instead of asking a level (ARCHITECTURE §3.3);
## use_level() is ignored, as the answers already are the right level's (E9).
## A question of another kind than the recorded answer, or past its end, means the replay
## diverged: it is reported in `diverged` and answered with the base class's defaults.

var diverged := false
var _answers: Array = []
var _next := 0


func _init(recorded: Array) -> void:
	_answers = recorded.duplicate()


## How many recorded answers no question has taken yet; more than 0 after a replay means it
## diverged.
func unread() -> int:
	return _answers.size() - _next


func line_of_sight(from: Vector3, to: Vector3) -> bool:
	var answer: Variant = _take(TYPE_BOOL)
	return answer if answer is bool else super.line_of_sight(from, to)


func floor_below(point: Vector3) -> Vector3:
	var answer: Variant = _take(TYPE_VECTOR3)
	return answer if answer is Vector3 else super.floor_below(point)


func rest_position(from: Vector3, towards: Vector3) -> Vector3:
	var answer: Variant = _take(TYPE_VECTOR3)
	return answer if answer is Vector3 else super.rest_position(from, towards)


func _take(type: Variant.Type) -> Variant:
	if _next >= _answers.size() or typeof(_answers[_next]) != type:
		if not diverged:
			push_error("replay: the recorded WorldQuery answers diverged at answer %d" % _next)
		diverged = true
		return null
	_next += 1
	return _answers[_next - 1]
