class_name SightHider
extends Node3D
## While the downed camera is in use (the own player downed, or a spectator watching a downed
## target), hides every view in GROUP that the body's eye could not see (ARCHITECTURE §4.7, the M4
## ADR's §3 item 3): the camera's arm, 2 m back over the body, would otherwise see past the end of a
## short wall the body lies against, more than standing at the body would. One ray per view per
## physics frame from `pivot` (the body's eye) to the view's sight point, against the world layer
## only; the level itself is public and stays drawn. Inactive, every view shows.
##
## A view joins GROUP: the remote avatars (AvatarViews), the bodies (BodyViews) and the items
## (M4-8's views) and the fill of each zone (ZoneViews, #650). It may give `sight_point()` (a
## Vector3) for where to look at it; else its origin. It runs after the avatars (-80) and the local player (0) have moved, so a view is
## hidden in the physics frame it appeared in.

const GROUP := &"hidden_out_of_sight"
const PHYSICS_PRIORITY := 10
## A hit this much short of the view's point still counts as seeing it: the view's own collision
## (an item on the world layer) or the floor under a lying body.
const SLACK_M := 0.1

## The body's eye, in world space, while active.
var pivot := Vector3.ZERO
var _active := false
## Views hidden by the last pass.
var _hidden: Array[Node3D] = []


func _init() -> void:
	process_physics_priority = PHYSICS_PRIORITY


## Starts hiding from `eye` (each physics frame until stop()), or moves the eye.
func watch_from(eye: Vector3) -> void:
	pivot = eye
	_active = true


## Stops hiding: every view hidden by it shows again.
func stop() -> void:
	_active = false
	for view: Node3D in _hidden:
		if is_instance_valid(view):
			view.visible = true
	_hidden.clear()


func is_active() -> bool:
	return _active


## One pass now (the physics frame calls it; tests may too).
func hide_unseen() -> void:
	if not _active:
		return
	var space := get_world_3d().direct_space_state
	var hidden: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var view := node as Node3D
		if view == null or not view.is_inside_tree():
			continue
		var seen := sees(space, pivot, _point_of(view))
		view.visible = seen
		if not seen:
			hidden.append(view)
	for view: Node3D in _hidden:
		if is_instance_valid(view) and not hidden.has(view):
			view.visible = true
	_hidden = hidden


## Whether `to` can be seen from `from`: no level geometry between them, short of SLACK_M.
static func sees(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	var reached := from.distance_to(hit["position"] as Vector3)
	return reached >= from.distance_to(to) - SLACK_M


func _physics_process(_delta: float) -> void:
	hide_unseen()


static func _point_of(view: Node3D) -> Vector3:
	if view.has_method(&"sight_point"):
		return view.call(&"sight_point") as Vector3
	return view.global_position
