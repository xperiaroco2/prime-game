class_name ItemState
extends RefCounted
## One item in MatchState's items table (ARCHITECTURE §9.1): its kind, where it is, and its
## position. Ids are assigned in spawn-point order, so an id says nothing about a task (§3.3).

## On the ground (interactive), in a hand, locked (a delivered package: not interactive), on a
## belt (vision revision 1, Two hands), or in flight (thrown, §7.1.16: not interactive until it
## rests). New values are appended, so that the older values keep theirs.
enum Where { GROUND, HAND, LOCKED, BELT, FLYING }

var id: int
var kind: ItemKind
var where := Where.GROUND
## The carrying player while `where` is HAND or BELT, else 0 (in flight too: the thrower is the
## flight's).
var holder := 0
## The rest position while on the ground or locked; while FLYING, the launch's origin o (the
## points of the arc come from `flight`).
var position := Vector3.ZERO
## The flight while `where` is FLYING (Items.launch), else null.
var flight: ItemFlight = null


func _init(item_id: int, item_kind: ItemKind, at: Vector3) -> void:
	id = item_id
	kind = item_kind
	position = at


## Whether a player carries it, in the hand or on the belt.
func is_carried() -> bool:
	return where == Where.HAND or where == Where.BELT


## Whether it is in flight (thrown and not yet at rest).
func is_in_flight() -> bool:
	return where == Where.FLYING
