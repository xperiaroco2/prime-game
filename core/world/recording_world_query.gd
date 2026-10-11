class_name RecordingWorldQuery
extends WorldQuery
## Wraps the WorldQuery Match is given and appends every answer to the command log, in order, so
## a replay can answer from the log without a level (ARCHITECTURE §3.3).

var _inner: WorldQuery
var _log: CommandLog


func _init(inner: WorldQuery, command_log: CommandLog) -> void:
	_inner = inner
	_log = command_log


## Forwarded; not an answer, so nothing is recorded (§4.5, E9).
func use_level(path: String) -> void:
	_inner.use_level(path)


func line_of_sight(from: Vector3, to: Vector3) -> bool:
	var answer := _inner.line_of_sight(from, to)
	_log.world_answers.append(answer)
	return answer


func floor_below(point: Vector3) -> Vector3:
	var answer := _inner.floor_below(point)
	_log.world_answers.append(answer)
	return answer


func stand_floor_below(point: Vector3) -> Vector3:
	var answer := _inner.stand_floor_below(point)
	_log.world_answers.append(answer)
	return answer


func rest_position(from: Vector3, towards: Vector3) -> Vector3:
	var answer := _inner.rest_position(from, towards)
	_log.world_answers.append(answer)
	return answer


func sweep(from: Vector3, to: Vector3, radius: float) -> Vector3:
	var answer := _inner.sweep(from, to, radius)
	_log.world_answers.append(answer)
	return answer
