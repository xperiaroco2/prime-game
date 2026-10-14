class_name BodyViews
extends Node3D
## The `Bodies` node under World (ARCHITECTURE §4.7 Others, E26): one view per body of the own
## ClientModel (Died puts one where the player died, the own player's included; Respawned and
## PlayerLeft remove it), drawn as the knockdown ADR's KD7 (a): the player's ragdoll keeps its pose,
## greyed, with a dark cross over the body's point (LifeLooks.cross). The ragdoll is the one
## AvatarViews drew while the player was knocked down, handed over in the step of the death
## (AvatarViews.release_ragdoll; this node steps after it); a body with none (a death this client
## never saw knocked down, a join after it) gets a fresh one lying at rest along -Z, since a body's
## facing is not sent. A dead ragdoll is on no layer (RagdollView.make_dead), so no ray stops at a
## body. Each view is in SightHider's group, so the downed camera shows no body the body's eye could
## not see; the view's visibility hides its ragdoll and cross alike. A handed-over ragdoll stays in
## the group too, by its own sight point, the same body point: taken out, a ragdoll the hider had
## hidden at the handover would stay hidden, since nothing else sets a grouped view's visibility.

const PHYSICS_PRIORITY := -70


## One body, at the body's point: its sight point is the lying capsule's middle over it.
class BodyView:
	extends Node3D
	var radius := 0.0
	## The dead player's ragdoll, top-level: the view's place does not move it.
	var ragdoll: RagdollView

	func sight_point() -> Vector3:
		return global_position + Vector3.UP * radius


var model: ClientModel
## The avatars, whose ragdoll of a player who just died becomes the body; null: every body gets a
## fresh ragdoll.
var avatars: AvatarViews
## The client's own copy of the mode's PlayerRules: the bodies' size.
var rules: PlayerRules

var _views: Dictionary[int, BodyView] = {}


func _init() -> void:
	name = "Bodies"
	process_physics_priority = PHYSICS_PRIORITY


## Draws the bodies of `client_model` at the size of `player_rules`, with `views`' ragdolls.
func setup(client_model: ClientModel, player_rules: PlayerRules, views: AvatarViews) -> void:
	model = client_model
	rules = player_rules
	avatars = views


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
			view.add_to_group(SightHider.GROUP)
			_views[peer] = view
			add_child(view)
			view.global_position = model.bodies[peer]
			view.ragdoll = _ragdoll_for(peer, model.bodies[peer])
			view.add_child(view.ragdoll)
			view.add_child(LifeLooks.cross(rules))
		view.global_position = model.bodies[peer]


## The ragdoll of `peer`'s body at `point`: the one AvatarViews hands over, else a fresh one lying
## at rest; greyed and held still either way.
func _ragdoll_for(peer: int, point: Vector3) -> RagdollView:
	var ragdoll := avatars.release_ragdoll(peer) if avatars != null else null
	if ragdoll == null:
		ragdoll = RagdollView.new()
		ragdoll.setup(rules, peer, LifeLooks.BODY_COLOUR)
		ragdoll.lie_at_rest(point, 0.0)
	ragdoll.name = "Ragdoll"
	ragdoll.make_dead(point)
	return ragdoll


func _physics_process(_delta: float) -> void:
	sync()
