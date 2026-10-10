class_name ItemViews
extends Node3D
## The items of the own ClientModel in 3D (ARCHITECTURE §4.7, Hands; M4-8): an ItemView per item
## the model knows, drawn from the model's fold of the item events (ItemSpawned, ItemPickedUp,
## Swapped, ItemPlaced, PackageDelivered, ItemThrown) and, in flight, from its arc (37e, §4.7.25):
## - nobody holds it: where it lies;
## - in flight: on its arc (`flights`, ItemFlights: the own throw predicted from the key press,
##   another's on the avatars' timeline, with the stop and a short fall at its rest), the same
##   depth-tested ItemView with no trail, outline or overlay; before the launch is drawn, at the
##   thrower's body as it is seen throwing it; hidden with no arc (a phase change hid it);
## - another player holds it: at that player's RemotePlayerBody, in its hand, on its belt, or a
##   two-handed item (the package) in front with both hands; hidden while that player has no body
##   drawn (no avatar in the newest snapshot);
## - the own living player holds it: hidden here; the hand item is drawn in the first-person view
##   (FirstPersonHand) and the belt item named on the HUD; from the throw key's press until the
##   host answers, the hand shows nothing (the item is on its predicted arc);
## - its holder is downed (it keeps its items, vision revision 1), the own player too: on the
##   ground at the body, and the first-person view shows none.
## Every view joins SightHider.GROUP, so the downed camera's sight hiding (M4-9) hides one out of
## the body's eye's sight, an item in flight too; only SightHider sets a view's `visible`,
## ItemViews shows or hides its look (and LifeView, after it, hides the looks of a spectated
## target's items seen from its eyes, #168). Placed in the physics step, after the avatars (-80)
## and the local player (0) moved and before SightHider (10) casts, so a view that appears or
## jumps out of the body's eye's sight is hidden in that same physics frame, never drawn for a
## frame first. The own arc's sweep reads the physics space, legal only in the physics step.
##
## The throw's sounds go out through `sound_due` when the drawn item launches and lands (ItemWorld
## connects it to WorldSounds, which cuts and muffles them like every world sound).

## A throw's launch or landing sound is due now: an event for WorldSounds.on_event.
signal sound_due(event_name: StringName, fields: Dictionary)

const PHYSICS_PRIORITY := 1

var model: ClientModel
## The client's own copy of the mode: which kinds take both hands, and the Throw rule's numbers.
var mode: GameMode
## The remote players' bodies, which carry their items, and the timeline they are drawn on.
var avatars: AvatarViews
## The local player: its hand item is drawn in its first-person view.
var player: PlayerController
## The items in flight and their arcs.
var flights := ItemFlights.new()

var _views: Dictionary[int, ItemView] = {}


func _init() -> void:
	process_physics_priority = PHYSICS_PRIORITY


## The item whose destination the HUD and the marker show (D10 (b)): the own hand's package, else
## the belt's; -1 for none.
static func destination_item(known: ClientModel) -> int:
	for item_id: int in [known.hand_item(known.own_peer), known.belt_item(known.own_peer)]:
		var item: ClientModel.Item = known.items.get(item_id)
		if item != null and item.station >= 0 and not item.delivered:
			return item_id
	return -1


## The view of item `id`, or null.
func view_of(id: int) -> ItemView:
	return _views.get(id)


func count() -> int:
	return _views.size()


## The session's events, already folded into the model (connected through ItemWorld): the arcs.
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if model == null:
		return
	var heard_at := float(avatars.host_tick()) if avatars != null else -1.0
	flights.on_event(event_name, fields, model, heard_at)
	_send_due()


## The throw key sent Throw as `seq`, from the camera at `eye` along `look`: the own hand item's
## predicted arc. False when nothing was predicted (no Throw rule for it, or one still waiting).
func predict_throw(seq: int, eye: Vector3, look: Vector3) -> bool:
	if model == null:
		return false
	var predicted := flights.predict(model, mode, seq, eye, look)
	_send_due()
	return predicted


## A throw waits for the host's answer (the throw key waits too).
func is_predicting() -> bool:
	return flights.is_predicting()


## Removes every view (the session ended).
func clear() -> void:
	for view: ItemView in _views.values():
		view.queue_free()
	_views.clear()
	flights.clear()
	if player != null:
		player.hand_view().show_item(&"", Color.WHITE)


func _physics_process(delta: float) -> void:
	if model == null:
		return
	for id: int in _views.keys():
		if not model.items.has(id):
			_views[id].queue_free()
			_views.erase(id)
	var drawn_at := avatars.drawn_at() if avatars != null else -1.0
	flights.advance(delta, drawn_at, model, _sweep)
	for id: int in model.items:
		var item := model.items[id]
		var view: ItemView = _views.get(id)
		if view == null:
			view = ItemView.make(id, item.kind, item.colour)
			view.add_to_group(SightHider.GROUP)
			_views[id] = view
			add_child(view)
		_place(view, item)
	_show_own_hand()
	_send_due()


func _place(view: ItemView, item: ClientModel.Item) -> void:
	var arc: ItemArc = flights.arcs.get(view.item_id)
	if arc != null:
		_place_in_flight(view, item, arc)
		return
	if item.flying:
		# In no hand and lying nowhere until its rest (§7.1.16), with no arc to draw: one still in
		# flight at a phase change stays hidden until its ItemPlaced.
		view.show_look(false)
		return
	if item.holder == ClientModel.NO_HOLDER:
		view.global_transform = Transform3D(Basis.IDENTITY, item.position)
		view.show_look(true)
		return
	var own := item.holder == model.own_peer
	var body := avatars.body_of(item.holder) if avatars != null and not own else null
	if model.life_of(item.holder) == ClientModel.Life.DOWNED:
		# Downed, the own player too: the downed camera looks at the own body from outside.
		var lying: Node3D = player if own else body
		if lying != null and lying.is_inside_tree():
			view.global_transform = Transform3D(Basis.IDENTITY, lying.global_position)
			view.show_look(true)
			return
	if own or body == null:
		view.show_look(false)
		return
	_place_at_body(view, item, body)


## On its arc; before the launch is drawn, in the thrower's hand as its body is seen (another
## player's throw on the avatars' timeline), hidden with no body to hold it.
func _place_in_flight(view: ItemView, item: ClientModel.Item, arc: ItemArc) -> void:
	var at := arc.position()
	if at.is_finite():
		view.global_transform = Transform3D(Basis.IDENTITY, at)
		view.show_look(true)
		return
	var body := avatars.body_of(arc.thrower) if avatars != null else null
	if body == null or arc.thrower == model.own_peer:
		view.show_look(false)
		return
	_place_at_body(view, item, body)


func _place_at_body(view: ItemView, item: ClientModel.Item, body: RemotePlayerBody) -> void:
	var point := body.belt_point()
	if not item.belted:
		point = body.carry_point() if _two_handed(item.kind) else body.hand_point()
	view.global_transform = point.global_transform
	view.show_look(true)


func _show_own_hand() -> void:
	if player == null or not player.is_inside_tree():
		return
	var hand_id := model.hand_item(model.own_peer)
	var hand: ClientModel.Item = model.items.get(hand_id)
	# Only the living look through the first-person camera; a downed player's items lie at its body.
	# A thrown item left the hand at the press, though the host has not answered yet.
	if hand == null or not model.is_alive(model.own_peer) or flights.hides_hand(hand_id):
		player.hand_view().show_item(&"", Color.WHITE)
	else:
		player.hand_view().show_item(hand.kind, hand.colour, _two_handed(hand.kind))


## The own arc's sweep (the throwing ADR's TE5 (a)): a sphere of `radius` from `from` towards `to`
## against the own scene's level, as the host's WorldQuery.sweep answers: `from` when it already
## touches the level there (cast_motion ignores what the shape already overlaps), else as far as
## cast_motion's safe fraction lets it go; `to` when nothing is in the way. Presentation only.
func _sweep(from: Vector3, to: Vector3, radius: float) -> Vector3:
	if not is_inside_tree() or radius <= 0.0 or not from.is_finite() or not to.is_finite():
		return to
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.collision_mask = PhysicsLayers.WORLD
	if player != null:
		query.exclude = [player.get_rid()]
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return from
	if from == to:
		return to
	query.motion = to - from
	var fractions := space.cast_motion(query)
	if fractions[0] >= 1.0:
		return to
	return from + (to - from) * fractions[0]


func _send_due() -> void:
	for due: Array in flights.take_due():
		sound_due.emit(due[0] as StringName, due[1] as Dictionary)


func _two_handed(item_kind: StringName) -> bool:
	var kind := mode.find_item_kind(item_kind) if mode != null else null
	return kind != null and kind.is_two_handed()
