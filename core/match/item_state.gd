class_name ItemState
extends RefCounted
## One item in MatchState's items table (ARCHITECTURE §9.1): its kind, where it is, and its
## position. Ids are assigned in spawn-point order, so an id says nothing about a task (§3.3).

## On the ground (interactive), in a hand, locked (a delivered package: not interactive), or on a
## belt (vision revision 1, Two hands). BELT comes last so that the older values keep theirs.
enum Where { GROUND, HAND, LOCKED, BELT }

var id: int
var kind: ItemKind
var where := Where.GROUND
## The carrying player while `where` is HAND or BELT, else 0.
var holder := 0
## The rest position while on the ground or locked.
var position := Vector3.ZERO


func _init(item_id: int, item_kind: ItemKind, at: Vector3) -> void:
	id = item_id
	kind = item_kind
	position = at


## Whether a player carries it, in the hand or on the belt.
func is_carried() -> bool:
	return where == Where.HAND or where == Where.BELT
