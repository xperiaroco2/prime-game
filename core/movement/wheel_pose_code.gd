class_name WheelPoseCode
extends RefCounted
## The pose wheel's whole pose as one byte (#1485; ARCHITECTURE §7.1.23): 0 for none, else the low
## nibble the leg stance's index + 1 and the high nibble the arm gesture's index + 1. The one place
## that packs and unpacks it: the snapshot's avatar, SelfStatus and later the booth's frame row and
## ShotTaken (#1476) all carry this byte. A mode's WheelPoses holds at most MAX_COUNT of each.

const NONE := 0
## The most leg stances, and the most arm gestures, a byte carries (a nibble each, 0 is none).
const MAX_COUNT := 15


## The byte of (legs, arms): NONE unless both are 0..MAX_COUNT - 1.
static func encode(legs: int, arms: int) -> int:
	if legs < 0 or arms < 0 or legs >= MAX_COUNT or arms >= MAX_COUNT:
		return NONE
	return (legs + 1) | ((arms + 1) << 4)


## The leg stance's index in `code`, or -1 for none.
static func legs_of(code: int) -> int:
	return (code & 0x0F) - 1 if is_pose(code) else -1


## The arm gesture's index in `code`, or -1 for none.
static func arms_of(code: int) -> int:
	return ((code >> 4) & 0x0F) - 1 if is_pose(code) else -1


## Whether `code` is a whole pose: a byte whose two nibbles are both set.
static func is_pose(code: int) -> bool:
	return code > 0 and code <= 0xFF and code & 0x0F != 0 and code & 0xF0 != 0


## Whether `code` is a byte this encoding can hold: NONE or a whole pose.
static func is_valid(code: int) -> bool:
	return code == NONE or is_pose(code)
