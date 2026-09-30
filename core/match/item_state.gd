class_name ItemState
extends RefCounted
## One item in MatchState's items table (ARCHITECTURE §9.1): its kind, where it is, and its
## position. Ids are assigned in spawn-point order, so an id says nothing about a task (§3.3).

## On the ground (interactive), in a hand, or locked (a delivered package: not interactive).
enum Where { GROUND, HAND, LOCKED }

var id: int
var kind: ItemKind
var where := Where.GROUND
## The holding player while `where` is HAND, else 0.
var holder := 0
## The rest position while on the ground or locked.
var position := Vector3.ZERO


func _init(item_id: int, item_kind: ItemKind, at: Vector3) -> void:
	id = item_id
	kind = item_kind
	position = at
