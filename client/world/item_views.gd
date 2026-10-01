class_name ItemViews
extends Node3D
## The items of the own ClientModel in 3D (ARCHITECTURE §4.7, Hands; M4-8): an ItemView per item
## the model knows, drawn from the model's fold of the item events only (ItemSpawned, ItemPickedUp,
## Swapped, ItemPlaced, PackageDelivered):
## - nobody holds it: where it lies;
## - another player holds it: at that player's RemotePlayerBody, in its hand, on its belt, or a
##   two-handed item (the package) in front with both hands; hidden while that player has no body
##   drawn (no avatar in the newest snapshot);
## - the own player holds it: hidden here; the hand item is drawn in the first-person view
##   (FirstPersonHand) and the belt item named on the HUD.
## - its holder is downed (it keeps its items, vision revision 1): on the ground at the body.
## Every view joins SightHider.GROUP, so the downed camera's sight hiding (M4-9) hides one out of
## the body's eye's sight; only SightHider sets a view's `visible`, ItemViews shows or hides its
## look. Placed in `_process`, after the avatars moved in the physics step.

var model: ClientModel
## The client's own copy of the mode: which kinds take both hands.
var mode: GameMode
## The remote players' bodies, which carry their items.
var avatars: AvatarViews
## The local player: its hand item is drawn in its first-person view.
var player: PlayerController

var _views: Dictionary[int, ItemView] = {}


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


## Removes every view (the session ended).
func clear() -> void:
	for view: ItemView in _views.values():
		view.queue_free()
	_views.clear()
	if player != null:
		player.hand_view().show_item(&"", Color.WHITE)


func _process(_delta: float) -> void:
	if model == null:
		return
	for id: int in _views.keys():
		if not model.items.has(id):
			_views[id].queue_free()
			_views.erase(id)
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


func _place(view: ItemView, item: ClientModel.Item) -> void:
	if item.holder == ClientModel.NO_HOLDER:
		view.global_transform = Transform3D(Basis.IDENTITY, item.position)
		view.show_look(true)
		return
	var body := avatars.body_of(item.holder) if avatars != null else null
	if item.holder == model.own_peer or body == null:
		view.show_look(false)
		return
	if model.life_of(item.holder) == ClientModel.Life.DOWNED:
		view.global_transform = Transform3D(Basis.IDENTITY, body.global_position)
		view.show_look(true)
		return
	var point := body.belt_point()
	if not item.belted:
		point = body.carry_point() if _two_handed(item.kind) else body.hand_point()
	view.global_transform = point.global_transform
	view.show_look(true)


func _show_own_hand() -> void:
	if player == null or not player.is_inside_tree():
		return
	var hand: ClientModel.Item = model.items.get(model.hand_item(model.own_peer))
	if hand == null:
		player.hand_view().show_item(&"", Color.WHITE)
	else:
		player.hand_view().show_item(hand.kind, hand.colour, _two_handed(hand.kind))


func _two_handed(item_kind: StringName) -> bool:
	var kind := mode.find_item_kind(item_kind) if mode != null else null
	return kind != null and kind.is_two_handed()
