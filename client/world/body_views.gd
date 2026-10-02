class_name BodyViews
extends Node3D
## The `Bodies` node under World (ARCHITECTURE §4.7 Others, E26): one view per body of the own
## ClientModel (Died puts one where the player died, the own player's included; Respawned and
## PlayerLeft remove it), drawn as the M4 ADR's D8 (a) placeholder, a grey lying capsule with a dark
## cross (LifeLooks). Each is in SightHider's group, so the downed camera shows no body the body's
## eye could not see. A body's facing is not sent: every body lies along -Z.

const PHYSICS_PRIORITY := -70


## One body: its sight point is the lying capsule's middle.
class BodyView:
	extends Node3D
	var radius := 0.0

	func sight_point() -> Vector3:
		return global_position + Vector3.UP * radius


var model: ClientModel
## The client's own copy of the mode's PlayerRules: the bodies' size.
var rules: PlayerRules

var _views: Dictionary[int, BodyView] = {}


func _init() -> void:
	name = "Bodies"
	process_physics_priority = PHYSICS_PRIORITY


## How many bodies are drawn.
func count() -> int:
	return _views.size()


## The view of `peer`'s body, or null.
func view_of(peer: int) -> Node3D:
	return _views.get(peer)


## Removes every view (the session ended).
func clear() -> void:
	for view: BodyView in _views.values():
		view.queue_free()
	_views.clear()


## Adds and removes views to match the model's bodies (called each physics frame, before
## SightHider's pass).
func sync() -> void:
	if model == null or rules == null:
		clear()
		return
	for peer: int in _views.keys():
		if not model.bodies.has(peer):
			_views[peer].queue_free()
			_views.erase(peer)
	for peer: int in model.bodies:
		var view: BodyView = _views.get(peer)
		if view == null:
			view = BodyView.new()
			view.name = "Body%d" % peer
			view.radius = rules.capsule_radius_m
			view.add_child(LifeLooks.body(rules))
			view.add_to_group(SightHider.GROUP)
			_views[peer] = view
			add_child(view)
		view.global_position = model.bodies[peer]


func _physics_process(_delta: float) -> void:
	sync()
