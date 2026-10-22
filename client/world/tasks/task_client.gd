class_name TaskClient
extends RefCounted
## What the client does for one core task type class (#1260, ARCHITECTURE §4.7.59): which station
## kinds E is answered for here, whether E offers one now, whether CircleViews draws a kind as a
## circle, and the view ItemWorld adds for the class. One subclass per core TaskType class, in
## `client/world/tasks/`, each with its row in TaskClients' table. Client-only and pure: from the
## own ClientModel and the client's own copy of the mode, never `core/` state; nothing here travels
## on the wire. The base answers nothing and makes no view.


## Whether this client answers E for station kind `kind_id` of `type` (StationUse.usable asks the
## first of the mode's types whose client owns the kind). The base: never.
func owns(_type: TaskType, _kind_id: StringName) -> bool:
	return false


## Whether E offers station `id` of `model`, of a kind of `type` this client owns, to the own
## player now (StationUse.usable has already checked the kind's Interact rule and the hand). The
## base: never.
func usable(_model: ClientModel, _type: TaskType, _id: int) -> bool:
	return false


## Whether CircleViews draws a station of `kind_id`, one of this client's type's station kinds, as
## a circle (#801's G6). The base: never (a kind no type of the mode holds is CircleViews' own
## fallback cylinder).
func draws_circle(_kind_id: StringName) -> bool:
	return false


## A new view for the class, named as ItemWorld's child, or null for none. ItemWorld sets the
## view's `model` and `mode` and, where the view has them, its `host_tick` and `level`, and at a
## reset calls its `clear()` if it has one and forgets the model and the host tick.
func make_view() -> Node3D:
	return null
