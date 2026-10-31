class_name WheelPoses
extends ContentPart
## The pose wheel's poses (#1485; GDD §8 "Photo", "The pose wheel"; ARCHITECTURE §7.1.23, §9.3): the
## leg stances and the arm gestures, an id each, in wheel order. A whole pose is one of each, sent
## as their indices (the WheelPose intent) and relayed as WheelPoseCode's byte, so each list holds
## 1 to WheelPoseCode.MAX_COUNT ids. An id is code (the wire's alphabet, ModeCheck.is_wire_id),
## not copy: the client's copy deck names them. The mode references it (GameMode.wheel_poses).

## The leg stances' ids, in wheel order.
@export var legs := PackedStringArray()
## The arm gestures' ids, in wheel order.
@export var arms := PackedStringArray()


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	found.append_array(_check_list("legs", legs))
	found.append_array(_check_list("arms", arms))
	return found


## Whether (`legs_index`, `arms_index`) is a whole pose of these lists: one of each.
func has_pick(legs_index: int, arms_index: int) -> bool:
	return (
		legs_index >= 0
		and legs_index < legs.size()
		and arms_index >= 0
		and arms_index < arms.size()
	)


static func _check_list(what: String, ids: PackedStringArray) -> PackedStringArray:
	var found := PackedStringArray()
	if ids.is_empty() or ids.size() > WheelPoseCode.MAX_COUNT:
		found.append(
			"%s holds %d ids, outside 1 to %d" % [what, ids.size(), WheelPoseCode.MAX_COUNT]
		)
	var seen := PackedStringArray()
	for id: String in ids:
		if not ModeCheck.is_wire_id(id):
			found.append(
				'%s id "%s" is not 1 to %d of a-z, 0-9 and _' % [what, id, ModeCheck.MAX_ID_LENGTH]
			)
		elif seen.has(id):
			found.append("%s id %s is listed twice" % [what, id])
		seen.append(id)
	return found
