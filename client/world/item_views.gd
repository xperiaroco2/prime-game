class_name ItemViews
extends Node3D
## The items of the own ClientModel in 3D (ARCHITECTURE §4.7, Hands; M4-8): an ItemView per item
## the model knows, drawn from the model's fold of the item events (ItemSpawned, ItemPickedUp,
## Swapped, ItemPlaced, PackageDelivered, ItemThrown) and, in flight, from its arc (37e, §4.7.52):
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
## A photo shows its shot's picture (PhotoPictures, #787) and a booth's strip its session's frames
## (StripPictures through the BoothBook, #1397), within PICTURE_RANGE_M; a strip just printed into
## the own hand slides in (FirstPersonHand.begin_slide).
##
## The throw's sounds go out through `sound_due` when the drawn item launches and lands (ItemWorld
## connects it to WorldSounds, which cuts and muffles them like every world sound).

## A throw's launch or landing sound is due now: an event for WorldSounds.on_event.
signal sound_due(event_name: StringName, fields: Dictionary)

const PHYSICS_PRIORITY := 1
## A photo farther than this from the drawing camera shows no picture, so its texture can go
## (PhotoPictures frees what nobody asks for). A look, "not a decision".
const PICTURE_RANGE_M := 12.0
## The second belt item (the higher belt place, GDD §6) hangs this far from the belt socket, in
## its frame, until the art gives the belt a second socket. A look, "not a decision" (#1218).
const SECOND_BELT_OFFSET := Vector3(-0.15, 0.0, 0.0)
## A strip the booth printed into the own hand slides in over this long (#1397). A look, "not a
## decision".
const PRINT_SLIDE_SECONDS := 0.6

var model: ClientModel
## The client's own copy of the mode: which kinds take both hands, and the Throw rule's numbers.
var mode: GameMode
## The remote players' bodies, which carry their items, and the timeline they are drawn on.
var avatars: AvatarViews
## The local player: its hand item is drawn in its first-person view.
var player: PlayerController
## The items in flight and their arcs.
var flights := ItemFlights.new()
## Where a resting item is drawn instead of its own position (ItemWorld's drawn_point): on a
## cooking station (CookingViews.point_of, #776) a Vector3; the film in a photo camera, a photo on
## the tray (a Vector3) or on the board (a Transform3D: upright) by PhotoViews.drawn_point (#787);
## null to draw it at its own position. Unset: at its own position.
var station_point := Callable()
## The shots' pictures (PhotoPictures, #787): a photo shows its shot's; unset: none.
var pictures: PhotoPictures
## The booth's strips (#1397): a strip shows its session's frames (StripPictures), found
## through the BoothBook that binds it; unset: none.
var strips: StripPictures
var booth: BoothBook

var _views: Dictionary[int, ItemView] = {}
## The model's Item each view was built for: ItemSpawned makes a new one, so a reused id shows.
var _built_for: Dictionary[int, ClientModel.Item] = {}


func _init() -> void:
	process_physics_priority = PHYSICS_PRIORITY


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
	_built_for.clear()
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
			_built_for.erase(id)
	var drawn_at := avatars.drawn_at() if avatars != null else -1.0
	flights.advance(delta, drawn_at, model, _sweep)
	for id: int in model.items:
		var item := model.items[id]
		var view: ItemView = _views.get(id)
		if (
			view != null
			and (view.kind != item.kind or view.parts != item.parts or _built_for.get(id) != item)
		):
			# The item changed kind (ItemChanged, cooking ADR CE4) or got its burger's parts
			# (BurgerPlated after its ItemSpawned, #1101), or its id was freed and reused within one
			# frame (ItemVanished, then ItemSpawned, CE3; the model holds a new Item, of the same kind
			# too): the old view's look is not this item's.
			view.queue_free()
			_views.erase(id)
			_built_for.erase(id)
			view = null
		if view == null:
			view = ItemView.make(id, item.kind, item.colour, mode, item.parts)
			view.add_to_group(SightHider.GROUP)
			_views[id] = view
			_built_for[id] = item
			add_child(view)
		_place(view, item)
		_show_picture(view, item, id)
	_show_own_hand()
	_send_due()


func _place(view: ItemView, item: ClientModel.Item) -> void:
	_outline(view, item)
	view.set_layer(
		PhotoLayers.GROUND if item.holder == ClientModel.NO_HOLDER else PhotoLayers.LIVE_AVATAR
	)
	var arc: ItemArc = flights.arcs.get(view.item_id)
	if arc != null:
		_place_in_flight(view, item, arc)
		return
	if item.flying:
		# In no hand and lying nowhere until its rest (§7.1.16), with no arc to draw: one still in
		# flight at a phase change stays hidden until its ItemPlaced.
		view.show_look(false)
		return
	if item.fitted:
		# Fitted to a car (PartFitted): locked at the car, drawn nowhere (RE12, #811).
		view.show_look(false)
		return
	if item.holder == ClientModel.NO_HOLDER:
		view.global_transform = _rest_point(view.item_id, item)
		view.show_look(true)
		return
	var own := item.holder == model.own_peer
	var body := avatars.body_of(item.holder) if avatars != null and not own else null
	if model.body_life_of(item.holder) == ClientModel.Life.DOWNED:
		# Downed or limp (§7.1.21), the own player too: the downed camera looks at the own body
		# from outside, and a limp body's upright capsule is hidden.
		var lying: Node3D = body
		if own:
			lying = player
		if lying != null and lying.is_inside_tree():
			var at := lying.global_position
			if own and avatars != null:
				# The own body moves with the host's (KE5), the controller holds still.
				at = avatars.point_of(item.holder, at)
			view.global_transform = Transform3D(Basis.IDENTITY, at)
			view.show_look(true)
			return
	if own or body == null:
		view.show_look(false)
		return
	_place_at_body(view, item, body)


## Where a resting item is drawn: on its plate or grill, in its camera, on the tray or the board
## (`station_point`), else where it lies.
func _rest_point(id: int, item: ClientModel.Item) -> Transform3D:
	if station_point.is_valid():
		var at: Variant = station_point.call(id)
		if at is Vector3:
			return Transform3D(Basis.IDENTITY, at as Vector3)
		if at is Transform3D:
			return at
	return Transform3D(Basis.IDENTITY, item.position)


## A plate's ingredient gets the filled slot's outline, the same whatever it is (#1101: nothing is
## right or wrong before a serve); the grill's patty and every other item none (#776). Set only
## when it changes.
func _outline(view: ItemView, item: ClientModel.Item) -> void:
	var want: Material = null
	if item.on_station >= 0 and model.stations.has(item.on_station):
		var kind := model.stations[item.on_station].kind
		var type := CookingUse.type_of(mode, kind)
		if CookingUse.role_of(type, kind) == CookingUse.Role.PLACE:
			want = CookingLooks.outline()
	# get_meta with a null default still errors on a missing key, and a null set_meta erases it.
	var had: Material = view.get_meta(&"outline") as Material if view.has_meta(&"outline") else null
	if had != want:
		view.set_meta(&"outline", want)
		CookingLooks.set_outline(view.look(), want)


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
	var at := point.global_transform
	if item.belted and model.items.get(model.belt_item2(item.holder)) == item:
		at = at.translated_local(SECOND_BELT_OFFSET)
	view.global_transform = at
	view.show_look(true)


func _show_own_hand() -> void:
	if player == null or not player.is_inside_tree():
		return
	var hand_id := model.hand_item(model.own_peer)
	var hand: ClientModel.Item = model.items.get(hand_id)
	# Only the living look through the first-person camera; a downed or limp player's items lie at
	# its body.
	# A thrown item left the hand at the press, though the host has not answered yet.
	if (
		hand == null
		or model.body_life_of(model.own_peer) != ClientModel.Life.ALIVE
		or flights.hides_hand(hand_id)
	):
		player.hand_view().show_item(&"", Color.WHITE)
	else:
		player.hand_view().show_item(
			hand.kind, hand.colour, _two_handed(hand.kind), hand_id, hand.parts
		)
		player.hand_view().set_picture(picture_for(hand, hand_id))
	# A strip just printed (#1397) slides up from the booth's slot into the hand.
	if booth != null and booth.take_fresh(hand_id):
		player.hand_view().begin_slide(PRINT_SLIDE_SECONDS)


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


## The picture item `item` (id `id`; -1: looked up in the model) shows: a photo its shot's
## texture (#787), a booth's strip its session's frames (#1397); null: no picture source, none
## yet, or no PhotoPictures or StripPictures.
func picture_for(item: ClientModel.Item, id := -1) -> Texture2D:
	if item == null:
		return null
	if StripLooks.has(item.kind):
		if strips == null or booth == null:
			return null
		if id < 0 and model != null:
			var key: Variant = model.items.find_key(item)
			id = key if key != null else -1
		return strips.texture_of(booth.session_of(id))
	if pictures == null or item.shot < 0:
		return null
	return pictures.texture_of(item.shot)


## A photo's or a strip's view shows its picture while its look is shown within PICTURE_RANGE_M of
## the drawing camera; else the blank, so the texture is no longer held and PhotoPictures frees
## it. An item with no picture source (no shot, not a strip) and no picture is left alone.
func _show_picture(view: ItemView, item: ClientModel.Item, id: int) -> void:
	if item.shot < 0 and not StripLooks.has(item.kind) and view.picture() == null:
		return
	var texture: Texture2D = null
	if view.look().visible and view.visible and _near(view.global_position):
		texture = picture_for(item, id)
	view.set_picture(texture)


func _near(at: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera == null or camera.global_position.distance_to(at) <= PICTURE_RANGE_M
